{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  versionCheckHook,
}:
let
  version = "0.70.1";
  hashes = {
    x86_64-linux = "sha256-P51gvPRlpK3SXpLufuWDA1d5Dkkv0pkb9vmCPq4pVMQ=";
    aarch64-linux = "sha256-XknxWctkoCWCvFA0h9Xrge25T2fVPt9JPQ6Hdhk8xdM=";
    aarch64-darwin = "sha256-7+s8bXdsnDg8gvFvPse+6xtj8hH9r8siLsTTKirmwnA=";
  };
  system = stdenvNoCC.hostPlatform.system;
  target =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    }
    .${system};
in
stdenvNoCC.mkDerivation {
  pname = "genteam-computer";
  inherit version;

  src = fetchurl {
    url = "https://cdn1.genspark.ai/releases/genteam-computer/${version}/genteam-computer-${target}.gz";
    hash = hashes.${system};
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    gunzip -c "$src" > "$out/bin/genteam-computer"
    chmod 755 "$out/bin/genteam-computer"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  preInstallCheck = ''
    export HOME=$(mktemp -d)
  '';
  postInstallCheck = ''
    "$out/bin/genteam-computer" --help > help.txt
    grep -q 'setup' help.txt
  '';

  meta = {
    description = "GenTeam Computer local agent runner";
    homepage = "https://www.genspark.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames hashes;
    mainProgram = "genteam-computer";
  };
}
