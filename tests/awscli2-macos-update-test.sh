#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MOCK_WORK="$WORK"
export MOCK_HASH='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

mkdir "$WORK/bin"
touch "$WORK/test-AWSCLIV2-2.100.0.pkg"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == 'api repos/aws/aws-cli/tags?per_page=100' ]]
cat "$MOCK_WORK/tags"
SH
cat >"$WORK/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 4 && $1 == store && $2 == prefetch-file && $3 == --json ]]
[[ $4 == https://awscli.amazonaws.com/AWSCLIV2-2.100.0.pkg ]]
printf 'fetch\n' >>"$MOCK_WORK/calls"
jq -nc --arg hash "$MOCK_HASH" --arg path "$MOCK_WORK/test-${4##*/}" '{hash: $hash, storePath: $path}'
SH
cat >"$WORK/bin/pkgutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 && $1 == --check-signature && -f $2 && $LC_ALL == C ]]
printf 'verify\n' >>"$MOCK_WORK/calls"
cat "$MOCK_WORK/signature"
exit "${MOCK_VERIFY_EXIT:-0}"
SH
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"

reset_case() {
  sed -E 's/^  version = "[^"]+";/  version = "2.99.0";/' \
    "$ROOT/nix/pkgs/awscli2-macos.nix" >"$WORK/before.nix"
  cp "$WORK/before.nix" "$WORK/package.nix"
  printf '%s\n' '[{"name":"2.101.0-beta.1"},{"name":"2.99.0"},{"name":"2.100.0"}]' >"$WORK/tags"
  printf '%s\n' \
    '   Status: signed by a developer certificate issued by Apple for distribution' \
    '    1. Developer ID Installer: AMZN Mobile LLC (94KV3E626L)' >"$WORK/signature"
  : >"$WORK/calls"
}

update() {
  bash "$ROOT/scripts/update-awscli2-macos" "$WORK/package.nix"
}

reject() {
  if update >"$WORK/output" 2>&1; then
    printf 'FAIL: invalid update was accepted: %s\n' "$1" >&2
    exit 1
  fi
  cmp "$WORK/before.nix" "$WORK/package.nix"
  [[ $(find "$WORK" -name 'package.nix.*' | wc -l) -eq 0 ]]
}

reset_case
update | jq -e '. == {update: true, version: "2.100.0"}' >/dev/null
sed -E \
  -e 's/^  version = "[^"]+";/  version = "2.100.0";/' \
  -e "s|^    hash = \"[^\"]+\";|    hash = \"$MOCK_HASH\";|" \
  "$WORK/before.nix" >"$WORK/expected.nix"
cmp "$WORK/expected.nix" "$WORK/package.nix"
[[ $(<"$WORK/calls") == $'fetch\nverify' ]]
: >"$WORK/calls"
update | jq -e '. == {update: false, version: "2.100.0"}' >/dev/null
printf '%s\n' '[{"name":"2.99.0"}]' >"$WORK/tags"
update | jq -e '.update == false' >/dev/null
[[ ! -s "$WORK/calls" ]]
cmp "$WORK/expected.nix" "$WORK/package.nix"

reset_case
sed -E 's/94KV3E626L/WRONGTEAM1/' "$WORK/signature" >"$WORK/changed"
mv "$WORK/changed" "$WORK/signature"
reject 'wrong Developer ID team'

reset_case
sed -E 's/1\. Developer/2. Developer/' "$WORK/signature" >"$WORK/changed"
mv "$WORK/changed" "$WORK/signature"
reject 'team found in the wrong certificate'

reset_case
printf '%s\n' '    1. Developer ID Installer: AMZN Mobile LLC (94KV3E626L)' >"$WORK/signature"
reject 'no trusted signature status'

reset_case
MOCK_VERIFY_EXIT=1 reject 'pkgutil verification failed'

reset_case
MOCK_HASH=invalid reject 'invalid hash'
[[ $(<"$WORK/calls") == fetch ]]

reset_case
printf '%s\n' '[{"name":"v2.100.0"},{"name":"2.101.0-rc.1"},{"name":"2.102.0;false"}]' >"$WORK/tags"
reject 'no stable release'
[[ ! -s "$WORK/calls" ]]

printf 'awscli2-macos update tests: PASS\n'
