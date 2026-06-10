{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bash,
  cacert,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  bzip2,
  xz,
  unzip,
  wget,
  patch,
}:

let
  release = import ../starrocks-release.nix;
  system = stdenvNoCC.hostPlatform.system;
  machine =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
      aarch64-darwin = "aarch64";
    }
    .${system} or (throw "StarRocks third-party source vendoring is not supported on ${system}");

  hashes = {
    x86_64-linux = "sha256-P020LK9s6/CxTtG84+zYpYCaYdzgGbfZSmdv7ThA93g=";
    aarch64-linux = "sha256-LVbsor1MVlK9jm8iq9UrU8kA67Ihc/UODqxGxx3Zqaw=";
    aarch64-darwin = "sha256-qjYJK0BgQVLD+LTJIg3glYgP7j1MC8K6XrL57sGveqs=";
  };

  awsCrtArchives =
    let
      fetchArchive =
        name: url: hash:
        fetchurl {
          name = "${name}.zip";
          inherit url hash;
        };
    in
    {
      aws-crt-cpp =
        fetchArchive "aws-crt-cpp"
          "https://codeload.github.com/awslabs/aws-crt-cpp/zip/e4514b7fb8b1fe67429aa7b0e00f628999722174"
          "sha256-9MdK0nOOyGkkOQ5XH0W2Fo19p8nbJ1S5aL41yoydCNY=";
      aws-c-auth =
        fetchArchive "aws-c-auth"
          "https://codeload.github.com/awslabs/aws-c-auth/zip/6ba7a0f8688c713dfe137716dbd5be324c2315b0"
          "sha256-2ZbYkDcTbff3C/XZ6O2tvizeXGuMa3GjcQfqsihPSME=";
      aws-c-cal =
        fetchArchive "aws-c-cal"
          "https://codeload.github.com/awslabs/aws-c-cal/zip/56f0a79ceb10f2efcf92f525ace717f84d8c8a11"
          "sha256-ocVtkdo90qpCYGQJ8l8TQW7dtM9IyMH5yCS9b5KjcIE=";
      aws-c-common =
        fetchArchive "aws-c-common"
          "https://codeload.github.com/awslabs/aws-c-common/zip/8eaa0986ad3cfd46c87432a2e4c8ab81a786085f"
          "sha256-UuCdrkLYRWYkCzc7Me1bP7xw3NMp9Nm5frbTbL2Aei4=";
      aws-c-compression =
        fetchArchive "aws-c-compression"
          "https://codeload.github.com/awslabs/aws-c-compression/zip/99ec79ee2970f1a045d4ced1501b97ee521f2f85"
          "sha256-7WoVgE97s+K6EH2Tr+lNy0AT3Lforus6ggd14hGHF4w=";
      aws-c-event-stream =
        fetchArchive "aws-c-event-stream"
          "https://codeload.github.com/awslabs/aws-c-event-stream/zip/63d1e1021b04ce3c3b1fc1895078ac85e0430b24"
          "sha256-YebplulHKkFVbYogYGpsxx9vh/nVwlHeqPUCpGys8BQ=";
      aws-c-http =
        fetchArchive "aws-c-http"
          "https://codeload.github.com/awslabs/aws-c-http/zip/6a1c157c20640a607102738909e89561a41e91e9"
          "sha256-qLNpZNjA4c6xbrd6bO2vSCIlnNZvvH1lmWn4MFPTuAA=";
      aws-c-io =
        fetchArchive "aws-c-io"
          "https://codeload.github.com/awslabs/aws-c-io/zip/6225ebb9da28f1023ad5e21694de9d165cd65f3b"
          "sha256-ZnqXN5PwtWvcNCWtvm/BM0QjG7jmBT28ZhGSS8dinAY=";
      aws-c-mqtt =
        fetchArchive "aws-c-mqtt"
          "https://codeload.github.com/awslabs/aws-c-mqtt/zip/17ee24a2177fc64cf9773d430a24e6fa06a89dd0"
          "sha256-mEebEd+3JeEeFSY/mLU9rfUP6+KRASRne6brERsRnlw=";
      aws-c-s3 =
        fetchArchive "aws-c-s3"
          "https://codeload.github.com/awslabs/aws-c-s3/zip/1dd55be83b19a55cd9c155e2da977cdc76112a91"
          "sha256-dQ8tQwR2Xn6oj9n+ExbpEdy29yF51kUVdaUcnlFZ+hw=";
      aws-c-sdkutils =
        fetchArchive "aws-c-sdkutils"
          "https://codeload.github.com/awslabs/aws-c-sdkutils/zip/fd8c0ba2e233997eaaefe82fb818b8b444b956d3"
          "sha256-deMc7gYjITzRCE0oNuyqOhQiF0nmofVWzapRgHKIhHQ=";
      aws-checksums =
        fetchArchive "aws-checksums"
          "https://codeload.github.com/awslabs/aws-checksums/zip/321b805559c8e911be5bddba13fcbd222a3e2d3a"
          "sha256-HZAxPZWoMNk9hxE71+yA5Z18FbFW+9K1Q7sv3t7WitE=";
      aws-lc =
        fetchArchive "aws-lc"
          "https://codeload.github.com/awslabs/aws-lc/zip/dc4e28145ceb6d46b5475e833f2da8def6d583fe"
          "sha256-TeecD45bAZv2tZ9qmq0+M34jeU+Jmzu18cntQVVi79A=";
      s2n =
        fetchArchive "s2n"
          "https://codeload.github.com/awslabs/s2n/zip/0998358a6ef7c4f22295deba088796fe354c5f4c"
          "sha256-4r57nUbltvSxnRgYkGdtnCS7evbQWRdSK0EWea0kAFw=";
    };

  awsCrtArchiveLinks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: archive: ''ln -s ${archive} "$STARROCKS_AWS_CRT_ARCHIVES_DIR/${name}.zip"''
    ) awsCrtArchives
  );

  gcsConnectorJar = fetchurl {
    url = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.11/gcs-connector-hadoop3-2.2.11-shaded.jar";
    hash = "sha256-wGc8osIC5BZ1rtA6zKVxgPGbv7kGUlrZf0DeirfTL6M=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "starrocks-thirdparty-sources";
  version = release.version;

  # Keep vendored source payloads byte-for-byte source-like. The normal fixup
  # phase can rewrite shebangs under $out/src to Nix store paths, which fixed
  # output derivations reject and downstream builds should not inherit.
  dontFixup = true;

  src = fetchFromGitHub {
    owner = release.sourceOwner;
    repo = release.sourceRepo;
    inherit (release) rev;
    hash = release.sourceHash;
  };

  nativeBuildInputs = [
    bash
    cacert
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    gnutar
    gzip
    bzip2
    xz
    unzip
    wget
    patch
  ];

  buildPhase = ''
    runHook preBuild

    cp -R thirdparty thirdparty-work
    chmod -R u+w thirdparty-work
    cd thirdparty-work

    patchShebangs .
    substituteInPlace vars.sh \
      --replace-fail 'MACHINE_TYPE=$(uname -m)' 'MACHINE_TYPE=${machine}' \
      --replace-fail 'BREAK_PAD HADOOPSRC JDK RAGEL HYPERSCAN' 'BREAK_PAD HADOOPSRC RAGEL HYPERSCAN'
    substituteInPlace vars.sh \
      --replace-fail 'https://fossies.org/linux/misc/bzip2-1.0.8.tar.gz' \
        'https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz'
    substituteInPlace download-thirdparty.sh \
      --replace-fail 'wget --progress=dot:mega --tries=3 --no-check-certificate' \
        'wget --progress=dot:mega --tries=3 --timeout=120 --read-timeout=120 --no-check-certificate'
    substituteInPlace download-thirdparty.sh \
      --replace-fail '    if [[ "''${STARROCKS_SKIP_THIRDPARTY_DOWNLOAD:-0}" == "1" ]]; then' \
        '    SOURCE=$TP_ARCH"_SOURCE"
    if [[ "''${STARROCKS_SKIP_EXTRACTED_THIRDPARTY_DOWNLOADS:-0}" == "1" && -n "''${!SOURCE}" && -d "$TP_SOURCE_DIR/''${!SOURCE}" ]]; then
        echo "Source ''${!SOURCE} already exists."
        continue
    fi

    if [[ "''${STARROCKS_SKIP_THIRDPARTY_DOWNLOAD:-0}" == "1" ]]; then'
    substituteInPlace vars-aarch64.sh \
      --replace-fail 'https://cdn-thirdparty.starrocks.com/jindosdk-4.6.8-linux-el7-aarch64.tar.gz' \
        'https://jindodata-binary.oss-cn-shanghai.aliyuncs.com/release/4.6.8/jindosdk-4.6.8-linux-el7-aarch64.tar.gz'
    ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
      export STARROCKS_TP_VARS_OVERRIDE=$PWD/vars-darwin-aarch64.sh
      export STARROCKS_SKIP_EXTRACTED_THIRDPARTY_DOWNLOADS=1
      mkdir -p src/gcs-connector-hadoop3-2.2.11-shaded
      cp ${gcsConnectorJar} src/gcs-connector-hadoop3-2.2.11-shaded/gcs-connector-hadoop3-2.2.11-shaded.jar
    ''}

    export STARROCKS_AWS_CRT_ARCHIVES_DIR=$TMPDIR/aws-crt-archives
    mkdir -p "$STARROCKS_AWS_CRT_ARCHIVES_DIR"
    ${awsCrtArchiveLinks}

    ./download-thirdparty.sh

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R src $out/src

    runHook postInstall
  '';

  outputHashMode = "recursive";
  outputHash = hashes.${system};

  meta = {
    description = "Vendored StarRocks third-party source archives for native builds";
    homepage = "https://github.com/StarRocks/starrocks";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
