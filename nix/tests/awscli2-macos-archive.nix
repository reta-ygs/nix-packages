{
  runCommand,
  fetchurl,
  xar,
  libarchive,
  file,
  jq,
  awscli2-macos,
}:
runCommand "awscli2-macos-archive-${awscli2-macos.version}"
  {
    src = fetchurl {
      inherit (awscli2-macos.src) url;
      hash = awscli2-macos.src.outputHash;
    };
    nativeBuildInputs = [
      xar
      libarchive
      file
      jq
    ];
  }
  ''
    ${awscli2-macos.unpackInstaller}
    for exe in aws aws_completer; do
      test -x "aws-cli/$exe"
      file -b "aws-cli/$exe" | grep -F 'Mach-O 64-bit arm64 executable'
    done
    test -s Resources/LICENSE.txt
    jq -e '
      .operations.GetScopedCredentials.input.shape as $shape
      | .shapes[$shape].members | has("Policy") and has("DurationSeconds")
    ' aws-cli/awscli/botocore/data/sts/2011-06-15/service-2.json >/dev/null
    touch "$out"
  ''
