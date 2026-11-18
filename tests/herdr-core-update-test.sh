#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MOCK_METADATA="$WORK/metadata.json" MOCK_CALLS="$WORK/calls"
export MOCK_WRITES="$WORK/writes" MOCK_PACKAGE="$WORK/package.nix"
REAL_CHMOD=$(command -v chmod)
REAL_MV=$(command -v mv)
export REAL_CHMOD REAL_MV

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$WORK/bin"
cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = '-fsSL --retry 3 https://releases.herdr.dev/core/latest.json' ]
[ "${MOCK_API_FAIL:-0}" = 0 ]
cat "$MOCK_METADATA"
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
[ "$1 $2 $3 $4 $5" = 'store prefetch-file --json --hash-type sha256' ]
printf '%s\n' "$6" >>"$MOCK_CALLS"
target=${6##*/herdr-core-}
target=${target%.tar.gz}
[ "${MOCK_DOWNLOAD_FAIL:-}" != "$target" ]
hex=$(jq -er --arg target "$target" '.targets[$target].sha256' "$MOCK_METADATA")
if [ "${MOCK_MISMATCH:-}" = "$target" ]; then
  hex=$(printf '%064d' 9)
fi
hash=$("$0" hash convert --hash-algo sha256 --to sri "$hex")
jq -nc --arg hash "${MOCK_BAD_HASH:-$hash}" '{hash: $hash}'
SH
cat >"$WORK/bin/chmod" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${MOCK_CHMOD_FAIL:-0}" = 0 ]
exec "$REAL_CHMOD" "$@"
SH
cat >"$WORK/bin/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${MOCK_MV_FAIL:-0}" = 0 ]
exec "$REAL_MV" "$@"
SH
chmod +x "$WORK/bin/"*

cat >"$WORK/base.nix" <<'NIX'
let
  hashes = {
    x86_64-linux = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    aarch64-linux = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{
  pname = "herdr-core";
  version = "0.1.18";
  inherit hashes;
}
NIX
jq -n '
  {version: "0.1.19", targets:
    (["linux-x86_64", "linux-aarch64"]
      | to_entries | map({key: .value, value: {
        url: ("https://releases.herdr.dev/core/0.1.19/herdr-core-" + .value + ".tar.gz"),
        sha256: ((.key + 1 | tostring) * 64)
      }}) | from_entries)
  }
' >"$WORK/valid.json"

reset_case() {
  cp "$WORK/valid.json" "$MOCK_METADATA"
  cp "$WORK/base.nix" "$MOCK_PACKAGE"
  cp "$MOCK_PACKAGE" "$WORK/before.nix"
  : >"$MOCK_CALLS"
}

update() {
  PATH="$WORK/bin:$PATH" bash "$ROOT/scripts/update-herdr-core" "$MOCK_PACKAGE"
}

reject() {
  if update >"$WORK/output" 2>&1; then
    fail "$1 was accepted"
  fi
  cmp "$WORK/before.nix" "$MOCK_PACKAGE" || fail "$1 changed the package"
  [ "$(find "$WORK" -name 'package.nix.*' | wc -l)" -eq 0 ] || fail "$1 left a temporary package"
}

reset_case
result=$(update)
jq -e '.update == true and .version == "0.1.19"' <<<"$result" >/dev/null
[ "$(wc -l <"$MOCK_CALLS")" -eq 2 ] || fail 'must download both Linux artifacts'
jq -r '.targets | to_entries[].value.url' "$MOCK_METADATA" >"$WORK/expected-urls"
cmp "$WORK/expected-urls" "$MOCK_CALLS" || fail 'unexpected artifact URLs or ordering'
cp "$MOCK_PACKAGE" "$WORK/updated.nix"
sed 's/0.1.18/0.1.19/' "$WORK/base.nix" >"$WORK/expected.nix"
systems=(x86_64-linux aarch64-linux)
targets=(linux-x86_64 linux-aarch64)
for i in "${!systems[@]}"; do
  hex=$(jq -r --arg target "${targets[$i]}" '.targets[$target].sha256' "$MOCK_METADATA")
  hash=$("$WORK/bin/nix" hash convert --hash-algo sha256 --to sri "$hex")
  sed -i -E "s|^    ${systems[$i]} = .*|    ${systems[$i]} = \"$hash\";|" "$WORK/expected.nix"
done
cmp "$WORK/expected.nix" "$MOCK_PACKAGE" || fail 'unexpected package changes or system mapping'
[ "$(stat -c '%a' "$MOCK_PACKAGE")" = 644 ]
: >"$MOCK_CALLS"
result=$(update)
jq -e '.update == false and .version == "0.1.19"' <<<"$result" >/dev/null
[ ! -s "$MOCK_CALLS" ] || fail 'repeat update downloaded artifacts'
cmp "$WORK/updated.nix" "$MOCK_PACKAGE"

for version in 0.1.18 0.1.9 0.0.99; do
  reset_case
  jq --arg version "$version" '.version = $version | .targets |= with_entries(.value.url |= sub("/0.1.19/"; "/" + $version + "/"))' \
    "$MOCK_METADATA" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_METADATA"
  result=$(update)
  jq -e '.update == false and .version == "0.1.18"' <<<"$result" >/dev/null
  cmp "$WORK/before.nix" "$MOCK_PACKAGE"
  [ ! -s "$MOCK_CALLS" ] || fail 'no-change or downgrade downloaded artifacts'
done

for expression in \
  '.version = "0.1.19;echo unsafe"' \
  '.version = "0.1.19-beta.1"' \
  '.version = "0.1.19+build"' \
  '.version = "v0.1.19"' \
  '.version = "00.1.19"' \
  '.version = "0.01.19"' \
  '.version = "0.1.019"' \
  '.version = "0.1.19\n"' \
  '.version = null' \
  '.version = 19' \
  '.targets = {}'; do
  reset_case
  jq "$expression" "$MOCK_METADATA" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_METADATA"
  reject "$expression"
  [ ! -s "$MOCK_CALLS" ] || fail 'invalid metadata initiated download'
done

for target in "${targets[@]}"; do
  for expression in \
    '.url = "https://example.com/asset"' \
    '.url |= sub("/0.1.19/"; "/0.1.20/")' \
    '.url += "?download=1"' \
    '.url |= sub("https:"; "http:")' \
    '.sha256 = "bad"' \
    '.sha256 = ("A" * 64)' \
    '.sha256 += "\n"' \
    '.sha256 = null' \
    'del(.sha256)'; do
    reset_case
    jq --arg target "$target" ".targets[\$target] |= ($expression)" "$MOCK_METADATA" >"$WORK/changed"
    mv "$WORK/changed" "$MOCK_METADATA"
    reject "$target: $expression"
    [ ! -s "$MOCK_CALLS" ] || fail 'must validate all manifest entries before downloading'
  done
  reset_case
  MOCK_MISMATCH="$target" reject "$target checksum mismatch"
  reset_case
  MOCK_DOWNLOAD_FAIL="$target" reject "$target download failure"
done

reset_case
MOCK_BAD_HASH='sha256-bad' reject 'invalid downloaded hash'
reset_case
MOCK_API_FAIL=1 reject 'manifest request failure'
reset_case
printf 'not json' >"$MOCK_METADATA"
reject 'invalid manifest JSON'
reset_case
MOCK_CHMOD_FAIL=1 reject 'atomic chmod failure'
[ "$(wc -l <"$MOCK_CALLS")" -eq 2 ]
reset_case
MOCK_MV_FAIL=1 reject 'atomic rename failure'
[ "$(wc -l <"$MOCK_CALLS")" -eq 2 ]

for operation in missing-version duplicate-version invalid-version; do
  reset_case
  case "$operation" in
    missing-version) sed -i '/^  version = /d' "$MOCK_PACKAGE" ;;
    duplicate-version) printf '  version = "0.1.18";\n' >>"$MOCK_PACKAGE" ;;
    invalid-version) sed -i 's/0.1.18/0.1.18-beta/' "$MOCK_PACKAGE" ;;
  esac
  cp "$MOCK_PACKAGE" "$WORK/before.nix"
  reject "$operation"
done
for system in "${systems[@]}"; do
  for operation in missing duplicate invalid; do
    reset_case
    case "$operation" in
      missing) sed -i "/^    $system = /d" "$MOCK_PACKAGE" ;;
      duplicate) printf '    %s = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";\n' "$system" >>"$MOCK_PACKAGE" ;;
      invalid) sed -i "s|^    $system = .*|    $system = \"sha256-bad\";|" "$MOCK_PACKAGE" ;;
    esac
    cp "$MOCK_PACKAGE" "$WORK/before.nix"
    reject "$operation $system hash"
  done
done
