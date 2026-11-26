{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage (finalAttrs: {
  pname = "genspark-cli";
  version = "1.16.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@genspark/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha512-aGBYbdH58VqmMOj9HSFri/pVViSVBaLNIGMSvM1bRPZ4giaTvgWkl3szr87FGYxM1wEg8XWV57+NVW9+1evG3A==";
  };

  postPatch = ''
    cp ${./genspark-cli-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-OFmSmtGQmFMnA2UObh05RFjbdRb1l6zgbwAYkWXDnWg=";
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
