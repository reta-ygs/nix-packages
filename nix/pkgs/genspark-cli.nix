{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage (finalAttrs: {
  pname = "genspark-cli";
  version = "1.16.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@genspark/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha512-CaEspyHcM2ebsldeHM9p+CSUn99HJAbmi0M5hZk2MNIHLlvgPADH22ZjL4T704e0cy0HAIHr3DzYjlx3bDi2Lw==";
  };

  postPatch = ''
    cp ${./genspark-cli-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-ShKlOq0i4GQ37UXYjj36unhC8GM8d3fOL/amKS3t45I=";
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
