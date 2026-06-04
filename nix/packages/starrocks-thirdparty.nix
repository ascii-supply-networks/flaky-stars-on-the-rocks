{
  lib,
  stdenv,
  fetchFromGitHub,
  callPackage,
  autoconf,
  automake,
  automake116x,
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
  writeShellScript,
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
  cmakeWithPolicy = writeShellScript "starrocks-cmake-with-policy" ''
    for arg in "$@"; do
      case "$arg" in
        --build|--install|--version|--help|-E|-P)
          exec ${cmake}/bin/cmake "$@"
          ;;
      esac
    done

    exec ${cmake}/bin/cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"
  '';
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
    automake116x
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
    patchShebangs thirdparty/src
    # Keep Ragel's vendored autotools/parser outputs newer than their inputs.
    # Otherwise make tries to regenerate them with unavailable automake-1.15.
    touch thirdparty/src/ragel-6.10/aclocal.m4
    touch thirdparty/src/ragel-6.10/configure
    find thirdparty/src/ragel-6.10 -name Makefile.in -exec touch {} +
    touch \
      thirdparty/src/ragel-6.10/ragel/rlparse.cpp \
      thirdparty/src/ragel-6.10/ragel/rlparse.h \
      thirdparty/src/ragel-6.10/ragel/rlscan.cpp
    substituteInPlace thirdparty/src/abseil-cpp-20220623.0/absl/container/internal/container_memory.h \
      --replace-fail '#include "absl/utility/utility.h"' '#include "absl/utility/utility.h"
    #include <cstdint>'
    substituteInPlace thirdparty/src/s2geometry-0.9.0/src/s2/third_party/absl/container/internal/container_memory.h \
      --replace-fail '#include "s2/third_party/absl/utility/utility.h"' '#include "s2/third_party/absl/utility/utility.h"
    #include <cstdint>'
    substituteInPlace thirdparty/src/llvm-project-18.1.8.src/llvm/include/llvm/ADT/SmallVector.h \
      --replace-fail '#include <cstddef>' '#include <cstddef>
    #include <cstdint>'
    substituteInPlace thirdparty/src/llvm-project-18.1.8.src/llvm/lib/Target/X86/MCTargetDesc/X86MCTargetDesc.h \
      --replace-fail '#include <string>' '#include <string>
    #include <cstdint>'
    substituteInPlace thirdparty/src/azure-storage-files-shares_12.12.0/sdk/attestation/azure-security-attestation/src/private/crypto/inc/crypto.hpp \
      --replace-fail '#include <vector>' '#include <vector>
    #include <cstdint>'
    substituteInPlace thirdparty/src/arrow-apache-arrow-19.0.1/cpp/cmake_modules/ThirdpartyToolchain.cmake \
      --replace-fail 'if(CMAKE_COMPILER_IS_GNUCC AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 15.0)' \
        'if(CMAKE_COMPILER_IS_GNUCC AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 15.0 AND
       ARROW_THRIFT_BUILD_VERSION VERSION_LESS 0.23.0)'
    for header in \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/Authentication.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/BrokerConsumerStats.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/Client.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/ClientConfiguration.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/Consumer.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/ConsumerConfiguration.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/Message.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/MessageBatch.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/MessageBuilder.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/ProducerConfiguration.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/Reader.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/ReaderConfiguration.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/c/consumer_configuration.h \
      thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/c/reader.h
    do
      substituteInPlace "$header" \
        --replace-fail '#include <pulsar/defines.h>' '#include <pulsar/defines.h>
    #include <stdint.h>'
    done
    substituteInPlace thirdparty/src/pulsar-client-cpp-3.3.0/include/pulsar/MessageIdBuilder.h \
      --replace-fail '#include <pulsar/MessageId.h>' '#include <pulsar/MessageId.h>
    #include <stdint.h>'
    substituteInPlace thirdparty/build-thirdparty.sh \
      --replace-fail 'export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ' \
        'export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g -Wno-error -Wno-array-bounds -Wno-error=array-bounds -Wno-stringop-overflow -Wno-error=stringop-overflow '
    substituteInPlace thirdparty/build-thirdparty.sh \
      --replace-fail 'export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ''${FILE_PREFIX_MAP_OPTION}"' \
        'export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -std=gnu17 ''${FILE_PREFIX_MAP_OPTION}"'
    perl -0pi -e '
      our $replaced;
      $replaced += s@(-Dxsimd_DIR=\$TP_INSTALL_DIR/share/cmake/xsimd \.\.\n\n)    \$\{BUILD_SYSTEM\} -j\$PARALLEL\n    \$\{BUILD_SYSTEM\} install@$1    if ! \$BUILD_SYSTEM -j\$PARALLEL; then\n        echo "Arrow parallel build failed; retrying serially for deterministic output"\n        \$BUILD_SYSTEM -j1 VERBOSE=1\n    fi\n    \$BUILD_SYSTEM install@;
      END { die "failed to patch build_arrow build command\n" unless $replaced }
    ' thirdparty/build-thirdparty.sh

    export STARROCKS_HOME=$PWD
    export STARROCKS_GCC_HOME=${stdenv.cc}
    export CUSTOM_CMAKE=${cmakeWithPolicy}
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
    while IFS= read -r -d "" link; do
      target=$(readlink "$link")
      case "$target" in
        "$PWD/thirdparty/installed/"*)
          targetInOut="$out/installed/''${target#"$PWD/thirdparty/installed/"}"
          ln -sfn "$(realpath --relative-to="$(dirname "$link")" "$targetInOut")" "$link"
          ;;
      esac
    done < <(find "$out/installed" -type l -print0)

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
