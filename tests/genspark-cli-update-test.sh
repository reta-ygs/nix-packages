#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/package"
export RELEASE="$work/metadata.json" TARBALL="$work/package.tgz" CALLS="$work/calls"
export SOURCE_HASH='sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
export DEPS_HASH='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

cat >"$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = '-fsSL --retry 3 https://registry.npmjs.org/@genspark%2fcli/latest' ]
cat "$RELEASE"
SH
cat >"$work/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1 $2 $3 $4 $5" = 'store prefetch-file --json --hash-type sha512' ]
[ "$6" = "$(jq -er .dist.tarball "$RELEASE")" ]
echo fetch >>"$CALLS"
jq -nc --arg hash "${ACTUAL:-$SOURCE_HASH}" --arg path "$TARBALL" '{hash: $hash, storePath: $path}'
SH
cat >"$work/bin/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = 'install --package-lock-only --ignore-scripts --no-audit --no-fund --registry=https://registry.npmjs.org' ]
echo npm >>"$CALLS"
[ "${FAIL_NPM:-0}" = 0 ]
jq '{name, version, lockfileVersion: 3}' package.json >package-lock.json
SH
cat >"$work/bin/prefetch-npm-deps" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
jq -e '.name == "@genspark/cli" and .version == "1.2.4" and .lockfileVersion == 3' "$1" >/dev/null
echo deps >>"$CALLS"
printf '%s\n' "${ACTUAL_DEPS:-$DEPS_HASH}"
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"

recipe="$work/package.nix"
lock="$work/package-lock.json"
sed -E 's/^  version = .*;/  version = "1.2.3";/' \
  "$root/nix/pkgs/genspark-cli.nix" >"$work/before.nix"
printf '%s\n' '{"name":"@genspark/cli","version":"1.2.3"}' >"$work/before.json"

update() {
  bash "$root/scripts/update-genspark-cli" "$recipe" "$lock"
}

release() {
  jq -nc --arg version "$1" --arg hash "$SOURCE_HASH" '{
    name: "@genspark/cli", version: $version,
    dist: {integrity: $hash, tarball: ("https://registry.npmjs.org/@genspark/cli/-/cli-" + $version + ".tgz")}
  }' >"$RELEASE"
}

tarball() {
  jq -nc --arg version "$1" '{name:"@genspark/cli", version: $version}' >"$work/package/package.json"
  tar -czf "$TARBALL" -C "$work" package/package.json
}

reset() {
  cp "$work/before.nix" "$recipe"
  cp "$work/before.json" "$lock"
  release 1.2.4
  tarball 1.2.4
  : >"$CALLS"
}

reject() {
  if update; then exit 1; fi
  cmp "$work/before.nix" "$recipe"
  cmp "$work/before.json" "$lock"
}

reset
update | jq -e '.update and .version == "1.2.4"' >/dev/null
grep -Fx '  version = "1.2.4";' "$recipe"
grep -Fx "    hash = \"$SOURCE_HASH\";" "$recipe"
grep -Fx "  npmDepsHash = \"$DEPS_HASH\";" "$recipe"
jq -e '.version == "1.2.4" and .lockfileVersion == 3' "$lock" >/dev/null
[ "$(<"$CALLS")" = $'fetch\nnpm\ndeps' ]
: >"$CALLS"
update | jq -e '(.update | not) and .version == "1.2.4"' >/dev/null
release 1.2.2
update | jq -e '(.update | not) and .version == "1.2.4"' >/dev/null
[ ! -s "$CALLS" ]

reset
jq '.dist.tarball += "?unexpected"' "$RELEASE" >"$work/invalid"
mv "$work/invalid" "$RELEASE"
reject
[ ! -s "$CALLS" ]
reset
ACTUAL=wrong reject
[ "$(<"$CALLS")" = fetch ]
reset
tarball 1.2.5
reject
[ "$(<"$CALLS")" = fetch ]
reset
FAIL_NPM=1 reject
[ "$(<"$CALLS")" = $'fetch\nnpm' ]
reset
ACTUAL_DEPS=wrong reject
