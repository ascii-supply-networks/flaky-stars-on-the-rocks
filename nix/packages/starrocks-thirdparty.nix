{
  lib,
  stdenv,
  fetchFromGitHub,
  callPackage,
  autoconf,
  automake,
  bash,
  binutils,
  bison,
  bzip2,
  byacc,
  cmake,
  coreutils,
  findutils,
  flex,
  gawk,
  gettext,
  gnumake,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  libtool,
  maven,
  ninja,
  openjdk21,
  jdk ? openjdk21,
  patch,
  perl,
  pkg-config,
  python3,
  unzip,
  util-linux,
  wget,
  which,
  xz,
  zip,
  starrocks-thirdparty-sources ? callPackage ./starrocks-thirdparty-sources.nix { },
}:

let
  release = import ../starrocks-release.nix;
  system = stdenv.hostPlatform.system;
  machine =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${system} or (throw "StarRocks third-party build is supported only on Linux, got ${system}");
in
stdenv.mkDerivation {
  pname = "starrocks-thirdparty";
  version = release.version;

  src = fetchFromGitHub {
    owner = release.sourceOwner;
    repo = release.sourceRepo;
    inherit (release) rev;
    hash = release.sourceHash;
  };

  nativeBuildInputs = [
    autoconf
    automake
    bash
    binutils
    bison
    bzip2
    byacc
    cmake
    coreutils
    findutils
    flex
    gawk
    gettext
    gnumake
    gnugrep
    gnused
    gnutar
    gzip
    libtool
    maven
    ninja
    jdk
    patch
    perl
    pkg-config
    python3
    unzip
    util-linux
    wget
    which
    xz
    zip
  ];

  dontUseCmakeConfigure = true;

  postPatch = ''
    patchShebangs thirdparty
    substituteInPlace thirdparty/vars.sh \
      --replace-fail 'MACHINE_TYPE=$(uname -m)' 'MACHINE_TYPE=${machine}' \
      --replace-fail 'BREAK_PAD HADOOPSRC JDK RAGEL HYPERSCAN' 'BREAK_PAD HADOOPSRC RAGEL HYPERSCAN'
    substituteInPlace thirdparty/build-thirdparty.sh \
      --replace-fail 'MACHINE_TYPE=$(uname -m)' 'MACHINE_TYPE=${machine}'
    perl -0pi -e '
      our $replaced;
      $replaced += s@build_jdk\(\) \{\n\s*check_if_source_exist \$JDK_SOURCE\n\s*rm -rf \$TP_INSTALL_DIR/open_jdk && cp -r \$TP_SOURCE_DIR/\$JDK_SOURCE \$TP_INSTALL_DIR/open_jdk\n\}@build_jdk() {\n    rm -rf \$TP_INSTALL_DIR/open_jdk\n    ln -s ${jdk} \$TP_INSTALL_DIR/open_jdk\n}@;
      END { die "failed to patch build_jdk\n" unless $replaced }
    ' thirdparty/build-thirdparty.sh
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"

    rm -rf thirdparty/src
    cp -R ${starrocks-thirdparty-sources}/src thirdparty/src
    chmod -R u+w thirdparty

    export STARROCKS_HOME=$PWD
    export STARROCKS_GCC_HOME=${stdenv.cc}
    export CUSTOM_CMAKE=${cmake}/bin/cmake
    export JAVA_HOME=${jdk}
    export PARALLEL=''${NIX_BUILD_CORES:-1}
    export THIRD_PARTY_BUILD_WITH_AVX2=OFF

    ./thirdparty/build-thirdparty.sh

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R thirdparty/installed $out/installed

    runHook postInstall
  '';

  meta = {
    description = "Native StarRocks third-party dependency tree built from source";
    homepage = "https://github.com/StarRocks/starrocks";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
