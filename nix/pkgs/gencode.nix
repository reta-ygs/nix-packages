{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  versionCheckHook,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gencode";
  version = "1.19.5-gencode.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@genspark/gencode-linux-x64-baseline/-/gencode-linux-x64-baseline-${finalAttrs.version}.tgz";
    hash = "sha512-O9ScTJlkUYQR05T0mxwOojH+IUoWdmhZCnAf3fwWa7RPqiG0ur6O+z/hMncvZj/QHNpiXdbKX+zbV/9yoPVPNw==";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/gencode "$out/bin/gencode"
    install -Dm644 LICENSE-opencode "$out/share/licenses/gencode/LICENSE-opencode"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  meta = {
    description = "Genspark AI coding agent for the terminal";
    homepage = "https://www.npmjs.com/package/@genspark/gencode";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "gencode";
  };
})
