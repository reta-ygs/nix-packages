{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  libarchive,
  jq,
  versionCheckHook,
}:
let
  unpackInstaller = ''
    xar -xf "$src"
    bsdtar -xf aws-cli.pkg/Payload
  '';
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "awscli2-macos";
  version = "2.42.1";

  src = fetchurl {
    url = "https://awscli.amazonaws.com/AWSCLIV2-${finalAttrs.version}.pkg";
    hash = "sha256-dOOKuKWStjXXsK6F5vM8sc66ec4ZwRLUJcu/U15geyM=";
  };

  nativeBuildInputs = [
    xar
    libarchive
  ];
  passthru = { inherit unpackInstaller; };
  unpackPhase = ''
    runHook preUnpack
    ${unpackInstaller}
    runHook postUnpack
  '';
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec" "$out/share/licenses/awscli2-macos"
    mv aws-cli "$out/libexec/"
    install -m 644 Resources/LICENSE.txt "$out/share/licenses/awscli2-macos/"
    ln -s ../libexec/aws-cli/aws "$out/bin/aws"
    ln -s ../libexec/aws-cli/aws_completer "$out/bin/aws_completer"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    jq
  ];
  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/aws";
  versionCheckProgramArg = "--version";
  preInstallCheck = ''
    export HOME=$(mktemp -d)
    export AWS_CONFIG_FILE="$HOME/config" AWS_SHARED_CREDENTIALS_FILE="$HOME/credentials"
    export AWS_EC2_METADATA_DISABLED=true
  '';
  postInstallCheck = ''
    "$out/bin/aws" --no-cli-pager sts get-scoped-credentials --generate-cli-skeleton input \
      | jq -e 'has("Policy") and has("DurationSeconds")' >/dev/null
  '';

  meta = {
    description = "AWS Command Line Interface v2 from the official macOS distribution";
    homepage = "https://aws.amazon.com/cli/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "aws";
  };
})
