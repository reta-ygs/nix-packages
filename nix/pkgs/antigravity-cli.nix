{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  versionCheckHook,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "antigravity-cli";
  version = "1.5.9";
  passthru.buildId = "4515810895593472";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${finalAttrs.version}-${finalAttrs.passthru.buildId}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha512-0B6xO6d1Du0YkH8a6IYIZDceCtkGRBXo0DPSK0vXubTkx/liBYUgtFLWfbHDMWPZqInVWn3/oVlZbsbNkah7eQ==";
  };

  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity "$out/libexec/antigravity"
    makeWrapper "$out/libexec/antigravity" "$out/bin/agy" \
      --set AGY_CLI_DISABLE_AUTO_UPDATE true
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/agy";
  versionCheckProgramArg = "--version";
  preInstallCheck = ''
    export HOME=$(mktemp -d)
  '';
  postInstallCheck = ''
    "$out/bin/agy" --help > help.txt 2>&1
    grep -q -- '--settings' help.txt
    grep -q -- '--mode.*auto' help.txt
    grep -q -- '--prompt-interactive' help.txt
  '';

  meta = {
    description = "Google Antigravity terminal agent";
    homepage = "https://antigravity.google/docs/getting-started?tab=cli";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "agy";
  };
})
