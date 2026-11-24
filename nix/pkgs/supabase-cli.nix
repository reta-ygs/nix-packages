{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  versionCheckHook,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "supabase-cli";
  version = "3.3.0";

  src = fetchurl {
    url = "https://github.com/supabase/cli/releases/download/v${finalAttrs.version}/supabase_${finalAttrs.version}_linux_amd64.tar.gz";
    hash = "sha256-jRJzGuUiqPJjFwynGbM/Fj3QX0NlrmwisxcU36HpK5s=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 supabase "$out/bin/supabase"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  preInstallCheck = ''
    export HOME=$(mktemp -d)
  '';
  postInstallCheck = ''
    $out/bin/supabase --help > /dev/null
  '';

  meta = {
    description = "CLI for interacting with Supabase";
    homepage = "https://github.com/supabase/cli";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "supabase";
  };
})
