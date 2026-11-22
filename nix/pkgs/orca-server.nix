{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  jq,
  stdenv,
  zlib,
  openssl,
  coreutils,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca-server";
  version = "1.4.271";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-server-linux-x64.tar.gz";
    hash = "sha256-pqbj06nsExdAoVZ53zR8uEgMfFjAVoesDdWXiGUSN2U=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    jq
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontAutoPatchelf = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/libexec/orca-server" "$out/bin"
    cp -a . "$out/libexec/orca-server/"

    makeWrapper "$out/libexec/orca-server/bin/orca-ide" "$out/bin/orca-ide" \
      --prefix PATH : "${lib.makeBinPath [ coreutils ]}"

    runHook postInstall
  '';

  postFixup = ''
    autoPatchelf "$out"
    runtime_hash=$(tr -d '\r\n' < "$out/libexec/orca-server/orcad/.runtime-node")
    node_bin="$out/libexec/orca-server/runtimes/node-$runtime_hash/bin/node"
    preflight_json=$(HOME=$(mktemp -d) "$node_bin" "$out/libexec/orca-server/orcad/orcad-server.js" --orcad-startup-preflight 00000000-0000-4000-8000-000000000001)
    artifact_version=$(jq -er '.artifactVersion' <<<"$preflight_json")
    printf '%s\n' "$artifact_version" > "$out/libexec/orca-server/orcad/.version"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    "$out/bin/orca-ide" --help > /dev/null
    runtime_hash=$(tr -d '\r\n' < "$out/libexec/orca-server/orcad/.runtime-node")
    node_bin="$out/libexec/orca-server/runtimes/node-$runtime_hash/bin/node"
    preflight_json=$("$node_bin" "$out/libexec/orca-server/orcad/orcad-server.js" --orcad-startup-preflight 00000000-0000-4000-8000-000000000002)
    actual_artifact=$(jq -er '.artifactVersion' <<<"$preflight_json")
    expected_artifact=$(tr -d '\r\n' < "$out/libexec/orca-server/orcad/.version")
    [ "$actual_artifact" = "$expected_artifact" ]
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
