#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MOCK_RELEASE="$WORK/release.json" MOCK_CALLS="$WORK/calls"
export MOCK_HASH='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = 'api repos/supabase/cli/releases/latest' ]
[ "${MOCK_API_FAIL:-0}" = 0 ]
cat "$MOCK_RELEASE"
SH
cat >"$WORK/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = hash ]; then
  [ "$1 $2 $3 $4 $5 $6" = 'hash convert --hash-algo sha256 --to sri' ]
  [ "$#" -eq 7 ]
  [[ $7 =~ ^[0-9a-f]{64}$ ]]
  printf 'sha256-'
  hex=$7
  for ((i = 0; i < ${#hex}; i += 2)); do
    printf '%b' "\\x${hex:i:2}"
  done | base64
  exit 0
fi
[ "$1 $2 $3" = 'store prefetch-file --json' ]
printf '%s\n' "$4" >>"$MOCK_CALLS"
[ "${MOCK_DOWNLOAD_FAIL:-0}" = 0 ]
jq -nc --arg hash "$MOCK_HASH" '{hash: $hash}'
SH
chmod +x "$WORK/bin/gh" "$WORK/bin/nix"

jq -n --arg digest "sha256:$(printf '%064d' 0)" '
  {
    tag_name: "v2.120.0", draft: false, prerelease: false,
    assets: [{name: "supabase_2.120.0_linux_amd64.tar.gz", digest: $digest,
      browser_download_url: "https://github.com/supabase/cli/releases/download/v2.120.0/supabase_2.120.0_linux_amd64.tar.gz"}]
  }
' >"$WORK/valid-release.json"

reset_case() {
  cp "$WORK/valid-release.json" "$MOCK_RELEASE"
  sed -E 's/^  version = "[^"]+";$/  version = "2.119.0";/' \
    "$ROOT/nix/pkgs/supabase-cli.nix" >"$WORK/package.nix"
  cp "$WORK/package.nix" "$WORK/before.nix"
  : >"$MOCK_CALLS"
}

update() {
  PATH="$WORK/bin:$PATH" bash "$ROOT/scripts/update-supabase-cli" "$WORK/package.nix"
}

reject() {
  if update >"$WORK/output" 2>&1; then
    fail "$1 was accepted"
  fi
  cmp "$WORK/before.nix" "$WORK/package.nix" || fail "$1 changed the package"
  [ "$(find "$WORK" -name 'package.nix.*' | wc -l)" -eq 0 ] || fail "$1 left a temporary package"
}

reset_case
result=$(update)
jq -e '.update == true and .version == "2.120.0"' <<<"$result" >/dev/null
sed -E \
  -e 's/^  version = "[^"]+";$/  version = "2.120.0";/' \
  -e "s|^    hash = \"[^\"]+\";$|    hash = \"$MOCK_HASH\";|" \
  "$WORK/before.nix" >"$WORK/expected.nix"
cmp "$WORK/expected.nix" "$WORK/package.nix" || fail 'unexpected package changes'
[ "$(wc -l <"$MOCK_CALLS")" -eq 1 ] || fail 'expected exactly one download'
[ "$(cat "$MOCK_CALLS")" = 'https://github.com/supabase/cli/releases/download/v2.120.0/supabase_2.120.0_linux_amd64.tar.gz' ]
: >"$MOCK_CALLS"
result=$(update)
jq -e '.update == false and .version == "2.120.0"' <<<"$result" >/dev/null
[ ! -s "$MOCK_CALLS" ] || fail 'repeat run downloaded assets'
cmp "$WORK/expected.nix" "$WORK/package.nix"

for tag in v2.119.0 v2.118.0 v2.99.0; do
  reset_case
  jq --arg tag "$tag" '.tag_name = $tag' "$MOCK_RELEASE" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_RELEASE"
  result=$(update)
  jq -e '.update == false and .version == "2.119.0"' <<<"$result" >/dev/null
  cmp "$WORK/before.nix" "$WORK/package.nix"
  [ ! -s "$MOCK_CALLS" ] || fail 'unchanged/older release downloaded assets'
done

for expression in \
  '.tag_name = "v2.120.0;echo unsafe"' \
  '.tag_name = "v2.120.0-beta.1"' \
  '.tag_name = "2.120.0"' \
  '.tag_name = "v02.120.0"' \
  '.draft = true' \
  '.prerelease = true' \
  'del(.draft)' \
  '.assets = []' \
  '.assets += [.assets[0]]' \
  '.assets[0].digest = "sha256:bad"' \
  '.assets[0].digest = null' \
  '.assets[0].browser_download_url = "https://example.com/asset"'; do
  reset_case
  jq "$expression" "$MOCK_RELEASE" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_RELEASE"
  reject "$expression"
done

reset_case
MOCK_HASH='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE=' reject 'checksum mismatch'
reset_case
MOCK_HASH='sha256-bad' reject 'invalid downloaded hash'
reset_case
MOCK_DOWNLOAD_FAIL=1 reject 'download failure'
reset_case
MOCK_API_FAIL=1 reject 'GitHub API failure'
reset_case
printf 'not json' >"$MOCK_RELEASE"
reject 'invalid API response'

for operation in missing-version duplicate-version missing-hash duplicate-hash; do
  reset_case
  case "$operation" in
    missing-version) sed -i '/^  version = /d' "$WORK/package.nix" ;;
    duplicate-version) printf '  version = "2.119.0";\n' >>"$WORK/package.nix" ;;
    missing-hash) sed -i '/^    hash = /d' "$WORK/package.nix" ;;
    duplicate-hash) printf '    hash = "%s";\n' "$MOCK_HASH" >>"$WORK/package.nix" ;;
  esac
  cp "$WORK/package.nix" "$WORK/before.nix"
  reject "$operation"
done
