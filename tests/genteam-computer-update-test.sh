#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MOCK_ROOT_MANIFEST="$WORK/root-manifest.json"
export MOCK_VERSION_MANIFEST="$WORK/version-manifest.json"
export MOCK_CALLS="$WORK/calls" MOCK_PACKAGE="$WORK/package.nix"
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
if [ "$*" = '-fsSL --retry 3 https://gensparkpublicblob.blob.core.windows.net/releases/genteam-computer/manifest.json' ]; then
  [ "${MOCK_ROOT_FAIL:-0}" = 0 ]
  cat "$MOCK_ROOT_MANIFEST"
  exit 0
fi
if [[ $* =~ ^-fsSL\ --retry\ 3\ https://cdn1\.genspark\.ai/releases/genteam-computer/([^/]+)/manifest\.json$ ]]; then
  [ "${MOCK_VERSION_FAIL:-0}" = 0 ]
  cat "$MOCK_VERSION_MANIFEST"
  exit 0
fi
exit 1
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
target=${6##*/genteam-computer-}
target=${target%.gz}
[ "${MOCK_DOWNLOAD_FAIL:-}" != "$target" ]
hex=$(jq -er --arg target "$target" '.targets[$target].gz.sha256' "$MOCK_VERSION_MANIFEST")
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
  version = "0.70.0";
  hashes = {
    x86_64-linux = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    aarch64-linux = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    aarch64-darwin = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{
  pname = "genteam-computer";
  inherit version hashes;
}
NIX
jq -n '
  {
    name: "genteam-computer",
    version: "0.70.1",
    targets: (
      ["linux-x64", "linux-arm64", "darwin-arm64"]
      | to_entries | map({
          key: .value,
          value: {
            file: ("genteam-computer-" + .value),
            sha256: ((.key + 4 | tostring) * 64),
            gz: {
              file: ("genteam-computer-" + .value + ".gz"),
              sha256: ((.key + 1 | tostring) * 64)
            }
          }
        }) | from_entries
    )
  }
' >"$WORK/valid.json"

reset_case() {
  cp "$WORK/valid.json" "$MOCK_ROOT_MANIFEST"
  cp "$WORK/valid.json" "$MOCK_VERSION_MANIFEST"
  cp "$WORK/base.nix" "$MOCK_PACKAGE"
  cp "$MOCK_PACKAGE" "$WORK/before.nix"
  : >"$MOCK_CALLS"
}

update() {
  PATH="$WORK/bin:$PATH" bash "$ROOT/scripts/update-genteam-computer" "$MOCK_PACKAGE"
}

reject() {
  if update >"$WORK/output" 2>&1; then
    fail "$1 was accepted"
  fi
  cmp "$WORK/before.nix" "$MOCK_PACKAGE" || fail "$1 changed the package"
  [ "$(find "$WORK" -name 'package.nix.*' | wc -l)" -eq 0 ] || fail "$1 left a temporary package"
}

systems=(x86_64-linux aarch64-linux aarch64-darwin)
targets=(linux-x64 linux-arm64 darwin-arm64)

reset_case
result=$(update)
jq -e '.update == true and .version == "0.70.1"' <<<"$result" >/dev/null
[ "$(wc -l <"$MOCK_CALLS")" -eq 3 ] || fail 'must download all three platform artifacts'
printf '%s\n' \
  'https://cdn1.genspark.ai/releases/genteam-computer/0.70.1/genteam-computer-linux-x64.gz' \
  'https://cdn1.genspark.ai/releases/genteam-computer/0.70.1/genteam-computer-linux-arm64.gz' \
  'https://cdn1.genspark.ai/releases/genteam-computer/0.70.1/genteam-computer-darwin-arm64.gz' \
  >"$WORK/expected-urls"
cmp "$WORK/expected-urls" "$MOCK_CALLS" || fail 'unexpected artifact URLs or ordering'
cp "$MOCK_PACKAGE" "$WORK/updated.nix"
sed 's/0.70.0/0.70.1/' "$WORK/base.nix" >"$WORK/expected.nix"
for i in "${!systems[@]}"; do
  hex=$(jq -r --arg target "${targets[$i]}" '.targets[$target].gz.sha256' "$MOCK_VERSION_MANIFEST")
  hash=$("$WORK/bin/nix" hash convert --hash-algo sha256 --to sri "$hex")
  sed -i -E "s|^    ${systems[$i]} = .*|    ${systems[$i]} = \"$hash\";|" "$WORK/expected.nix"
done
cmp "$WORK/expected.nix" "$MOCK_PACKAGE" || fail 'unexpected package changes or system mapping'
[ "$(stat -c '%a' "$MOCK_PACKAGE")" = 644 ]
: >"$MOCK_CALLS"
result=$(update)
jq -e '.update == false and .version == "0.70.1"' <<<"$result" >/dev/null
[ ! -s "$MOCK_CALLS" ] || fail 'repeat update downloaded artifacts'
cmp "$WORK/updated.nix" "$MOCK_PACKAGE"

for version in 0.70.0 0.69.9 0.9.99; do
  reset_case
  jq --arg version "$version" '.version = $version' "$MOCK_ROOT_MANIFEST" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_ROOT_MANIFEST"
  result=$(update)
  jq -e '.update == false and .version == "0.70.0"' <<<"$result" >/dev/null
  cmp "$WORK/before.nix" "$MOCK_PACKAGE"
  [ ! -s "$MOCK_CALLS" ] || fail 'no-change or downgrade downloaded artifacts'
done

for expression in \
  '.version = "0.70.1;echo unsafe"' \
  '.version = "0.70.1-beta.1"' \
  '.version = "0.70.1+build"' \
  '.version = "v0.70.1"' \
  '.version = "00.70.1"' \
  '.version = "0.070.1"' \
  '.version = "0.70.01"' \
  '.version = "0.70.1\n"' \
  '.version = null' \
  '.version = 70'; do
  reset_case
  jq "$expression" "$MOCK_ROOT_MANIFEST" >"$WORK/changed"
  mv "$WORK/changed" "$MOCK_ROOT_MANIFEST"
  reject "root $expression"
  [ ! -s "$MOCK_CALLS" ] || fail 'invalid root metadata initiated download'
done

reset_case
jq '.version = "0.70.2"' "$MOCK_VERSION_MANIFEST" >"$WORK/changed"
mv "$WORK/changed" "$MOCK_VERSION_MANIFEST"
reject 'version manifest mismatch'
[ ! -s "$MOCK_CALLS" ] || fail 'mismatched version manifest initiated download'

reset_case
jq '.targets = {}' "$MOCK_VERSION_MANIFEST" >"$WORK/changed"
mv "$WORK/changed" "$MOCK_VERSION_MANIFEST"
reject 'empty targets'
[ ! -s "$MOCK_CALLS" ] || fail 'empty targets initiated download'

for target in "${targets[@]}"; do
  for expression in \
    '.gz.file = "wrong.gz"' \
    '.gz.file = null' \
    '.gz.sha256 = "bad"' \
    '.gz.sha256 = ("A" * 64)' \
    '.gz.sha256 += "\n"' \
    '.gz.sha256 = null' \
    'del(.gz)'; do
    reset_case
    jq --arg target "$target" ".targets[\$target] |= ($expression)" "$MOCK_VERSION_MANIFEST" >"$WORK/changed"
    mv "$WORK/changed" "$MOCK_VERSION_MANIFEST"
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
MOCK_ROOT_FAIL=1 reject 'root manifest request failure'
reset_case
MOCK_VERSION_FAIL=1 reject 'version manifest request failure'
reset_case
printf 'not json' >"$MOCK_ROOT_MANIFEST"
reject 'invalid root manifest JSON'
reset_case
printf 'not json' >"$MOCK_VERSION_MANIFEST"
reject 'invalid version manifest JSON'
reset_case
MOCK_CHMOD_FAIL=1 reject 'atomic chmod failure'
[ "$(wc -l <"$MOCK_CALLS")" -eq 3 ]
reset_case
MOCK_MV_FAIL=1 reject 'atomic rename failure'
[ "$(wc -l <"$MOCK_CALLS")" -eq 3 ]

for operation in missing-version duplicate-version invalid-version; do
  reset_case
  case "$operation" in
    missing-version) sed -i '/^  version = /d' "$MOCK_PACKAGE" ;;
    duplicate-version) printf '  version = "0.70.0";\n' >>"$MOCK_PACKAGE" ;;
    invalid-version) sed -i 's/0.70.0/0.70.0-beta/' "$MOCK_PACKAGE" ;;
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
