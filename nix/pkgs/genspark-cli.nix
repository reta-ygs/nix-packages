{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage (finalAttrs: {
  pname = "genspark-cli";
  version = "1.14.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@genspark/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha512-7f4Y2nqhWxE1mkp/D14fs/BGdRvcMbZNxUfoe0jdUrKCIXZcYED5+K4Zoi1C3pRVQKEhqj23yDLY/6TybQ0+Cw==";
  };

  postPatch = ''
    cp ${./genspark-cli-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-PrX4NqbKtk4YkiDHb1M2GYqKCW0Jvrlhm7fLgxmR9PQ=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    for command in gsk genspark; do
      test "$($out/bin/$command --version)" = "${finalAttrs.version}"
      $out/bin/$command --help > help.txt
      grep -q 'login' help.txt
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for the Genspark AI platform";
    homepage = "https://www.npmjs.com/package/@genspark/cli";
    license = lib.licenses.mit;
    mainProgram = "gsk";
  };
})
