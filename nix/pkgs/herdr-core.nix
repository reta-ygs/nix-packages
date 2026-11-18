{
  lib,
  stdenvNoCC,
  fetchurl,
  versionCheckHook,
}:
let
  version = "0.1.21";
  hashes = {
    x86_64-linux = "sha256-eEJHVcEKQN3jigvbVcIKwZcG6a4F7Wj8Ks8fz/DZQcE=";
    aarch64-linux = "sha256-6ESiv6tIoiYJdnnQdryDBC/lf8zvU4fvgC5bJOeLUpo=";
  };
  system = stdenvNoCC.hostPlatform.system;
  target =
    {
      x86_64-linux = "linux-x86_64";
      aarch64-linux = "linux-aarch64";
    }
    .${system};
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/herdr-core-${target}.tar.gz";
    hash = hashes.${system};
  };

  sourceRoot = ".";
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/doc/herdr-core"
    install -m755 herdr-core "$out/bin/herdr-core"
    ln -s herdr-core "$out/bin/hc"
    install -m644 LICENSE THIRD-PARTY-NOTICES "$out/share/doc/herdr-core/"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  preInstallCheck = ''
    export HOME=$(mktemp -d)
  '';
  postInstallCheck = ''
    "$out/bin/hc" --help > /dev/null
    "$out/bin/hc" --skill > /dev/null
  '';

  meta = {
    description = "Persistent terminals for programs and coding agents";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames hashes;
    mainProgram = "hc";
  };
}
