{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  stdenv,
  zlib,
  openssl,
  coreutils,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca-server";
  version = "1.4.269";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-server-linux-x64.tar.gz";
    hash = "sha256-8oFWwM7anQNNnFXif1wLc/ON5w5OyLS6jXQMAPJtDnQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/libexec/orca-server" "$out/bin"
    cp -a . "$out/libexec/orca-server/"

    makeWrapper "$out/libexec/orca-server/bin/orca-ide" "$out/bin/orca-ide" \
      --prefix PATH : "${lib.makeBinPath [ coreutils ]}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    "$out/bin/orca-ide" --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Orca headless server and CLI (orca-ide)";
    homepage = "https://orca.dev";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca-ide";
  };
})
