#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MOCK_METADATA="$WORK/metadata.json" MOCK_CALLS="$WORK/calls"
export MOCK_HASH='sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$WORK/bin"
cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = '-fsSL --retry 3 https://registry.npmjs.org/@genspark%2fgencode-linux-x64-baseline/latest' ]
[ "${MOCK_API_FAIL:-0}" = 0 ]
cat "$MOCK_METADATA"
SH
cat >"$WORK/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1 $2 $3 $4 $5" = 'store prefetch-file --json --hash-type sha512' ]
printf '%s\n' "$6" >>"$MOCK_CALLS"
[ "${MOCK_DOWNLOAD_FAIL:-0}" = 0 ]
jq -nc --arg hash "$MOCK_HASH" '{hash: $hash}'
SH
chmod +x "$WORK/bin/curl" "$WORK/bin/nix"

url='https://registry.npmjs.org/@genspark/gencode-linux-x64-baseline/-/gencode-linux-x64-baseline-1.19.3-gencode.2.tgz'
jq -n --arg url "$url" --arg integrity "$MOCK_HASH" '{name: "@genspark/gencode-linux-x64-baseline", version: "1.19.3-gencode.2", dist: {tarball: $url, integrity: $integrity}}' >"$WORK/valid.json"

reset_case() {
  cp "$WORK/valid.json" "$MOCK_METADATA"
  sed -E 's/^  version = "[^"]+";$/  version = "1.18.32-gencode.1";/' \
    "$ROOT/nix/pkgs/gencode.nix" >"$WORK/package.nix"
  cp "$WORK/package.nix" "$WORK/before.nix"
  : >"$MOCK_CALLS"
}

update() {
  PATH="$WORK/bin:$PATH" bash "$ROOT/scripts/update-gencode" "$WORK/package.nix"
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
jq -e '.update == true and .version == "1.19.3-gencode.2"' <<<"$result" >/dev/null
sed -E \
  -e 's/^  version = "[^"]+";$/  version = "1.19.3-gencode.2";/' \
  -e "s|^    hash = \"[^\"]+\";$|    hash = \"$MOCK_HASH\";|" \
  "$WORK/before.nix" >"$WORK/expected.nix"
cmp "$WORK/expected.nix" "$WORK/package.nix" || fail 'unexpected package changes'
[ "$(cat "$MOCK_CALLS")" = "$url" ] || fail 'unexpected download URL'
: >"$MOCK_CALLS"
result=$(update)
jq -e '.update == false and .version == "1.19.3-gencode.2"' <<<"$result" >/dev/null
[ ! -s "$MOCK_CALLS" ] || fail 'repeat run downloaded tarball'
cmp "$WORK/expected.nix" "$WORK/package.nix"

for version in 1.18.32-gencode.1 1.17.99-gencode.5; do
  reset_case
  jq --arg version "$version" --arg url "https://registry.npmjs.org/@genspark/gencode-linux-x64-baseline/-/gencode-linux-x64-baseline-$version.tgz" '.version = $version | .dist.tarball = $url' "$MOCK_METADATA" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_METADATA"
  result=$(update)
  jq -e '.update == false and .version == "1.18.32-gencode.1"' <<<"$result" >/dev/null
  cmp "$WORK/before.nix" "$WORK/package.nix"
  [ ! -s "$MOCK_CALLS" ] || fail 'old version downloaded tarball'
done

for expression in \
  '.version = "1.19.3-gencode.2;echo unsafe"' \
  '.version = "1.19.3-gencode.2-beta"' \
  '.version = "01.19.3-gencode.2"' \
  '.version = null' \
  '.name = "unrelated"' \
  '.dist.tarball = "https://example.com/asset"' \
  '.dist.integrity = "sha512-bad"' \
  'del(.dist.integrity)'; do
  reset_case
  jq "$expression" "$MOCK_METADATA" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_METADATA"
  version=$(jq -r '.version // empty' "$MOCK_METADATA")
  if [[ $expression == '.version = '* ]] && [ -n "$version" ]; then
    jq --arg url "https://registry.npmjs.org/@genspark/gencode-linux-x64-baseline/-/gencode-linux-x64-baseline-$version.tgz" \
      '.dist.tarball = $url' "$MOCK_METADATA" >"$WORK/changed"
    mv "$WORK/changed" "$MOCK_METADATA"
  fi
  reject "$expression"
done

reset_case
MOCK_HASH='sha512-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB==' reject 'integrity mismatch'
reset_case
MOCK_DOWNLOAD_FAIL=1 reject 'download failure'
reset_case
MOCK_API_FAIL=1 reject 'registry failure'
reset_case
printf 'not json' >"$MOCK_METADATA"
reject 'invalid metadata'

for operation in missing-version duplicate-version missing-hash duplicate-hash; do
  reset_case
  case "$operation" in
    missing-version) sed -i '/^  version = /d' "$WORK/package.nix" ;;
    duplicate-version) printf '  version = "1.18.32-gencode.1";\n' >>"$WORK/package.nix" ;;
    missing-hash) sed -i '/^    hash = /d' "$WORK/package.nix" ;;
    duplicate-hash) printf '    hash = "%s";\n' "$MOCK_HASH" >>"$WORK/package.nix" ;;
  esac
  cp "$WORK/package.nix" "$WORK/before.nix"
  reject "$operation"
done
