#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
export MANIFEST="$work/manifest.json" CALLS="$work/downloads"
export REAL_NIX
REAL_NIX=$(command -v nix)
export HASH
HASH=$(nix hash convert --hash-algo sha512 --to sri "$(printf '%0128d' 7)")

cat >"$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = '-fsSL --retry 3 https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json' ]
cat "$MANIFEST"
SH
cat >"$work/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = hash ]; then
  exec "$REAL_NIX" "$@"
fi
[ "$1 $2 $3 $4 $5" = 'store prefetch-file --json --hash-type sha512' ]
[ "$6" = "$(jq -er .url "$MANIFEST")" ]
printf '%s\n' "$6" >>"$CALLS"
jq -nc --arg hash "${ACTUAL:-$HASH}" '{hash: $hash}'
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"

recipe="$work/package.nix"
sed -E \
  -e 's/^  version = .*;/  version = "1.2.3";/' \
  -e 's/^  passthru\.buildId = .*;/  passthru.buildId = "123";/' \
  "$root/nix/pkgs/antigravity-cli.nix" >"$work/before"

update() {
  bash "$root/scripts/update-antigravity-cli" "$recipe"
}

manifest() {
  jq -nc --arg version "$1" --arg build "$2" --arg sha "$(printf '%0128d' 7)" '{
    version: $version,
    url: ("https://storage.googleapis.com/antigravity-public/antigravity-cli/" + $version + "-" + $build + "/linux-x64/cli_linux_x64.tar.gz"),
    sha512: $sha
  }' >"$MANIFEST"
}

cp "$work/before" "$recipe"
manifest 1.2.4 456
update | jq -e '.update and .version == "1.2.4"' >/dev/null
grep -Fx '  version = "1.2.4";' "$recipe"
grep -Fx '  passthru.buildId = "456";' "$recipe"
grep -Fx "    hash = \"$HASH\";" "$recipe"
[ "$(wc -l <"$CALLS")" -eq 1 ]
update | jq -e '(.update | not) and .version == "1.2.4"' >/dev/null
manifest 1.2.2 900
update | jq -e '(.update | not) and .version == "1.2.4"' >/dev/null
[ "$(wc -l <"$CALLS")" -eq 1 ]
manifest 1.2.4 789
update | jq -e '.update and .version == "1.2.4"' >/dev/null
grep -Fx '  passthru.buildId = "789";' "$recipe"

for mutation in '.url += "?foo=1"' '.url |= sub("storage.googleapis.com"; "example.com")' \
  '.sha512 += "\n"' '.version += "\n"'; do
  cp "$work/before" "$recipe"
  manifest 1.2.4 456
  jq "$mutation" "$MANIFEST" >"$work/rejected"
  mv "$work/rejected" "$MANIFEST"
  : >"$CALLS"
  if update; then exit 1; fi
  [ ! -s "$CALLS" ]
  cmp "$work/before" "$recipe"
done

manifest 1.2.4 456
if ACTUAL=wrong update; then exit 1; fi
cmp "$work/before" "$recipe"
