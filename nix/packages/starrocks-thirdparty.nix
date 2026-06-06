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
  cyrus_sasl,
  findutils,
  flex,
  gawk,
  gettext,
  gperftools,
  gnumake,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  libtool,
  llvmPackages,
  maven,
  ninja,
  openjdk21,
  jdk ? openjdk21,
  patch,
  perl,
  pkg-config,
  pcre2,
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
  isDarwin = stdenv.hostPlatform.isDarwin;
  isLinux = stdenv.hostPlatform.isLinux;
  linuxParallel = "\${NIX_BUILD_CORES:-1}";
  machine =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
      aarch64-darwin = "aarch64";
    }
    .${system} or (throw "StarRocks third-party build is not supported on ${system}");
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
  darwinArWrapper = writeShellScript "starrocks-darwin-ar" ''
    set -euo pipefail

    original=("$@")
    case "''${1:-}" in
      --version|-V|-h|--help|-M)
        exec /usr/bin/ar "''${original[@]}"
        ;;
    esac

    while [[ $# -gt 0 ]]; do
      case "$1" in
        *.a|*/*.a)
          break
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ $# -eq 0 ]]; then
      exec /usr/bin/ar "''${original[@]}"
    fi

    archive="$1"
    shift

    objects=()
    for object in "$@"; do
      if [[ "''${object}" == @* ]]; then
        list_file="''${object#@}"
        while IFS= read -r entry; do
          [[ -n "''${entry}" ]] && objects+=("''${entry}")
        done < "''${list_file}"
      else
        objects+=("''${object}")
      fi
    done

    if [[ ''${#objects[@]} -eq 0 ]]; then
      : > "''${archive}"
      exit 0
    fi

    tmp="$(mktemp "''${archive}.tmp.XXXXXX")"
    rm -f "''${tmp}"

    inputs=()
    if [[ -f "''${archive}" ]]; then
      inputs+=("''${archive}")
    fi
    inputs+=("''${objects[@]}")

    /usr/bin/libtool -static -o "''${tmp}" "''${inputs[@]}"
    mv "''${tmp}" "''${archive}"
  '';
  darwinRanlibWrapper = writeShellScript "starrocks-darwin-ranlib" ''
    exit 0
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

  __noChroot = isDarwin;

  dontUseCmakeConfigure = true;
  dontStrip = isDarwin;

  postPatch = ''
    patchShebangs thirdparty
    ${lib.optionalString isLinux ''
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
    ''}
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    ${lib.optionalString isDarwin ''
      export PATH="$PATH:/usr/bin:/usr/sbin:/bin:/sbin"
      export HOMEBREW_NO_AUTO_UPDATE=1
      export STARROCKS_USE_NIX_DEPS=1
      export PCRE2_ROOT_DIR="$PWD/thirdparty/nix-pcre2-root"
    ''}

    rm -rf thirdparty/src
    cp -R ${starrocks-thirdparty-sources}/src thirdparty/src
    chmod -R u+w thirdparty
    ${lib.optionalString isDarwin ''
      mkdir -p thirdparty/nix-pcre2-root/bin thirdparty/nix-pcre2-root/include thirdparty/nix-pcre2-root/lib/pkgconfig
      ln -s ${pcre2.dev}/bin/pcre2-config thirdparty/nix-pcre2-root/bin/pcre2-config
      for header in ${pcre2.dev}/include/pcre2*.h; do
        ln -s "$header" "thirdparty/nix-pcre2-root/include/$(basename "$header")"
      done
      for library in ${pcre2.out}/lib/libpcre2*; do
        ln -s "$library" "thirdparty/nix-pcre2-root/lib/$(basename "$library")"
      done
      for metadata in ${pcre2.dev}/lib/pkgconfig/libpcre2*.pc; do
        ln -s "$metadata" "thirdparty/nix-pcre2-root/lib/pkgconfig/$(basename "$metadata")"
      done
    ''}
    patchShebangs thirdparty/src
    ${lib.optionalString isDarwin ''
            for file in \
              thirdparty/src/brpc-1.9.0/src/butil/file_util_mac.mm \
              thirdparty/src/brpc-1.9.0/src/butil/mac/bundle_locations.h \
              thirdparty/src/brpc-1.9.0/src/butil/mac/foundation_util.h \
              thirdparty/src/brpc-1.9.0/src/butil/memory/singleton_objc.h \
              thirdparty/src/brpc-1.9.0/src/butil/strings/sys_string_conversions_mac.mm \
              thirdparty/src/brpc-1.9.0/src/butil/threading/platform_thread_mac.mm
            do
              substituteInPlace "$file" \
                --replace-fail '#import <Foundation/Foundation.h>' '#include <sys/_types.h>
            #ifndef _UUID_STRING_T
            #define _UUID_STRING_T
            typedef __darwin_uuid_string_t uuid_string_t;
            #endif
            #import <Foundation/Foundation.h>'
            done
            substituteInPlace thirdparty/src/brpc-1.9.0/src/butil/mac/foundation_util.h \
              --replace-fail '#include <ApplicationServices/ApplicationServices.h>' '#include <sys/_types.h>
            #ifndef _UUID_STRING_T
            #define _UUID_STRING_T
            typedef __darwin_uuid_string_t uuid_string_t;
            #endif
            #include <ApplicationServices/ApplicationServices.h>'
            perl -0pi -e '
              our $replaced;
              $replaced += s/\bu_int\b/unsigned int/g;
              END { die "failed to patch Darwin brpc flat_map unsigned type\n" unless $replaced == 6 }
            ' \
              thirdparty/src/brpc-1.9.0/src/butil/containers/flat_map.h \
              thirdparty/src/brpc-1.9.0/src/butil/containers/flat_map_inl.h
            substituteInPlace thirdparty/src/starrocks-clucene-2026.04.09/src/shared/CLucene/LuceneThreads.h \
              --replace-fail '#define  _LuceneThreads_h


      CL_NS_DEF(util)' '#define  _LuceneThreads_h

      #if defined(_CL_HAVE_PTHREAD)
      #include <pthread.h>
      #endif

      CL_NS_DEF(util)'
                perl -0pi -e '
                  our $replaced;
                  $replaced += s@ensure_formula\(\) \{\n    local formula="\$1"\n    if ! brew list --formula "\$\{formula\}" >/dev/null 2>&1; then\n        brew install "\$\{formula\}"\n    fi\n\}@ensure_formula() {\n    :\n}@;
                  END { die "failed to patch Darwin Homebrew installer\n" unless $replaced }
                ' thirdparty/build-thirdparty-darwin.sh
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail 'brew --prefix "$1"' 'printf "%s\n" "''${HOMEBREW_PREFIX:-/opt/homebrew}/opt/$1"'
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_gtest\(\) \{\n    ensure_formula googletest\n    local prefix\n    prefix="\$\(formula_prefix googletest\)"\n    link_children_if_missing "\$\{prefix\}/include" "\$\{TP_INCLUDE_DIR\}"\n    link_matching_if_missing "\$\{TP_INSTALL_DIR\}/lib" "\$\{prefix\}/lib/libgtest\*.a" "\$\{prefix\}/lib/libgmock\*.a" "\$\{prefix\}/lib/libgtest\*.dylib" "\$\{prefix\}/lib/libgmock\*.dylib"\n    sync_lib64_links\n\}@build_formula_gtest() {\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        check_if_source_exist "\$GTEST_SOURCE"\n        cd "\$TP_SOURCE_DIR/\$GTEST_SOURCE"\n        rm -rf "\$BUILD_DIR"\n        mkdir -p "\$BUILD_DIR"\n        cd "\$BUILD_DIR"\n        "\$CMAKE_CMD" -G "\$CMAKE_GENERATOR" \\\n            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \\\n            -DCMAKE_INSTALL_PREFIX="\$TP_INSTALL_DIR" \\\n            -DCMAKE_INSTALL_LIBDIR=lib \\\n            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \\\n            -DBUILD_GMOCK=ON \\\n            -DBUILD_GTEST=ON \\\n            ..\n        "\$BUILD_SYSTEM" -j"\$PARALLEL"\n        "\$BUILD_SYSTEM" install\n        if [[ ! -f "\$TP_INCLUDE_DIR/gtest/gtest_prod.h" ]]; then\n            echo "gtest header missing after source install: \$TP_INCLUDE_DIR/gtest/gtest_prod.h"\n            exit 1\n        fi\n        if [[ ! -f "\$TP_INSTALL_DIR/lib/libgtest.a" ]]; then\n            echo "gtest static library missing after source install: \$TP_INSTALL_DIR/lib/libgtest.a"\n            exit 1\n        fi\n        if [[ ! -f "\$TP_INSTALL_DIR/lib/libgmock.a" ]]; then\n            echo "gmock static library missing after source install: \$TP_INSTALL_DIR/lib/libgmock.a"\n            exit 1\n        fi\n        sync_lib64_links\n        return 0\n    fi\n    ensure_formula googletest\n    local prefix\n    prefix="\$(formula_prefix googletest)"\n    link_children_if_missing "\''${prefix}/include" "\''${TP_INCLUDE_DIR}"\n    link_matching_if_missing "\''${TP_INSTALL_DIR}/lib" "\''${prefix}/lib/libgtest*.a" "\''${prefix}/lib/libgmock*.a" "\''${prefix}/lib/libgtest*.dylib" "\''${prefix}/lib/libgmock*.dylib"\n    sync_lib64_links\n}@;
                    END { die "failed to patch Darwin gtest source build\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    s@(-DCMAKE_INSTALL_LIBDIR=lib \\\n)(            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \\\n            -DBUILD_GMOCK=ON)@$1            -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy" \\\n$2@ or die "failed to patch Darwin gtest warning flags\n";
                  ' thirdparty/build-thirdparty-darwin.sh
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail '        local bshuf_cflags="-I./src -I./lz4 -I''${TP_INCLUDE_DIR}/lz4 -std=c99 -O3 -DNDEBUG -fPIC"

              "''${CC}" ''${bshuf_cflags} ''${arch_flag} -c src/bitshuffle_core.c -o bitshuffle_core.o
              "''${CC}" ''${bshuf_cflags} ''${arch_flag} -c src/bitshuffle.c -o bitshuffle.o
              "''${CC}" ''${bshuf_cflags} ''${arch_flag} -c src/iochain.c -o iochain.o' '        local bshuf_cflags="-I./src -I./lz4 -I''${TP_INCLUDE_DIR}/lz4 -std=c99 -O3 -DNDEBUG -fPIC"
              local rename_header=""
              if [[ "''${arch}" == "neon" ]]; then
                  if [[ ! -f bitshuffle_default.o ]]; then
                      echo "bitshuffle default object missing before NEON symbol rename"
                      exit 1
                  fi
                  "''${NM_BIN}" -gU bitshuffle_default.o \
                      | awk "{ name=\$3; sub(/^_/, \"\", name); if (name != \"\") print \"#define \" name \" \" name \"_neon\" }" \
                      > renames_neon.h
                  rename_header="-include ''${PWD}/renames_neon.h"
              fi

              "''${CC}" ''${bshuf_cflags} ''${arch_flag} ''${rename_header} -c src/bitshuffle_core.c -o bitshuffle_core.o
              "''${CC}" ''${bshuf_cflags} ''${arch_flag} ''${rename_header} -c src/bitshuffle.c -o bitshuffle.o
              "''${CC}" ''${bshuf_cflags} ''${arch_flag} ''${rename_header} -c src/iochain.c -o iochain.o'
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail '            "''${OBJCOPY}" --redefine-syms=renames.txt "''${tmp_obj}" "''${dst_obj}"' '            mv "''${tmp_obj}" "''${dst_obj}"'
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail '        to_link="''${to_link} ''${dst_obj}"' '        if [[ "''${arch}" == "neon" ]]; then
                  if ! otool -hv "''${dst_obj}" | grep -q "MH_MAGIC_64"; then
                      echo "bitshuffle NEON object is not a 64-bit Mach-O object"
                      exit 1
                  fi
                  if ! "''${NM_BIN}" -gU "''${dst_obj}" | grep -q "_bshuf_compress_lz4_neon"; then
                      echo "bitshuffle NEON symbols missing after compile-time rename"
                      exit 1
                  fi
              fi

              to_link="''${to_link} ''${dst_obj}"'
                  perl -0pi -e '
                    our $replaced;
                  $replaced += s@build_formula_rapidjson\(\) \{\n    ensure_formula rapidjson\n    local prefix\n    prefix="\$\(formula_prefix rapidjson\)"\n    link_if_missing "\$\{prefix\}/include/rapidjson" "\$\{TP_INCLUDE_DIR\}/rapidjson"\n    link_formula_metadata "\$\{prefix\}"\n\}@build_formula_rapidjson() {\n    ensure_formula rapidjson\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        check_if_source_exist "\$RAPIDJSON_SOURCE"\n        mkdir -p "\$TP_INCLUDE_DIR"\n        rm -rf "\$TP_INCLUDE_DIR/rapidjson"\n        cp -R "\$TP_SOURCE_DIR/\$RAPIDJSON_SOURCE/include/rapidjson" "\$TP_INCLUDE_DIR/rapidjson"\n        if [[ ! -f "\$TP_INCLUDE_DIR/rapidjson/rapidjson.h" ]]; then\n            echo "RapidJSON header missing after source install: \$TP_INCLUDE_DIR/rapidjson/rapidjson.h"\n            exit 1\n        fi\n        return 0\n    fi\n    local prefix\n    prefix="\$(formula_prefix rapidjson)"\n    link_if_missing "\''${prefix}/include/rapidjson" "\''${TP_INCLUDE_DIR}/rapidjson"\n    link_formula_metadata "\''${prefix}"\n}@;
                    END { die "failed to patch Darwin rapidjson source install\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_fast_float\(\) \{\n    ensure_formula fast_float\n    local prefix\n    prefix="\$\(formula_prefix fast_float\)"\n    link_if_missing "\$\{prefix\}/include/fast_float" "\$\{TP_INCLUDE_DIR\}/fast_float"\n\}@build_formula_fast_float() {\n    ensure_formula fast_float\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        check_if_source_exist "\$FAST_FLOAT_SOURCE"\n        mkdir -p "\$TP_INCLUDE_DIR"\n        rm -rf "\$TP_INCLUDE_DIR/fast_float"\n        cp -R "\$TP_SOURCE_DIR/\$FAST_FLOAT_SOURCE/include/fast_float" "\$TP_INCLUDE_DIR/fast_float"\n        if [[ ! -f "\$TP_INCLUDE_DIR/fast_float/fast_float.h" ]]; then\n            echo "fast_float header missing after source install: \$TP_INCLUDE_DIR/fast_float/fast_float.h"\n            exit 1\n        fi\n        return 0\n    fi\n    local prefix\n    prefix="\$(formula_prefix fast_float)"\n    link_if_missing "\''${prefix}/include/fast_float" "\''${TP_INCLUDE_DIR}/fast_float"\n}@;
                    END { die "failed to patch Darwin fast_float source install\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_opentelemetry\(\) \{\n    ensure_formula opentelemetry-cpp\n    local prefix\n    prefix="\$\(formula_prefix opentelemetry-cpp\)"\n    link_children_if_missing "\$\{prefix\}/include" "\$\{TP_INCLUDE_DIR\}"\n    link_matching_if_missing "\$\{TP_INSTALL_DIR\}/lib" "\$\{prefix\}/lib/libopentelemetry"\*.a "\$\{prefix\}/lib/libopentelemetry"\*.dylib\n    link_formula_metadata "\$\{prefix\}"\n    sync_lib64_links\n\}@build_formula_opentelemetry() {\n    ensure_formula opentelemetry-cpp\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        check_if_source_exist "\$OPENTELEMETRY_SOURCE"\n        mkdir -p "\$TP_INCLUDE_DIR"\n        rm -rf "\$TP_INCLUDE_DIR/opentelemetry"\n        cp -R "\$TP_SOURCE_DIR/\$OPENTELEMETRY_SOURCE/api/include/opentelemetry" "\$TP_INCLUDE_DIR/opentelemetry"\n        if [[ ! -f "\$TP_INCLUDE_DIR/opentelemetry/common/attribute_value.h" ]]; then\n            echo "OpenTelemetry header missing after source install: \$TP_INCLUDE_DIR/opentelemetry/common/attribute_value.h"\n            exit 1\n        fi\n        return 0\n    fi\n    local prefix\n    prefix="\$(formula_prefix opentelemetry-cpp)"\n    link_children_if_missing "\''${prefix}/include" "\''${TP_INCLUDE_DIR}"\n    link_matching_if_missing "\''${TP_INSTALL_DIR}/lib" "\''${prefix}/lib/libopentelemetry"*.a "\''${prefix}/lib/libopentelemetry"*.dylib\n    link_formula_metadata "\''${prefix}"\n    sync_lib64_links\n}@;
                    END { die "failed to patch Darwin OpenTelemetry source install\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_sasl\(\) \{\n    ensure_formula cyrus-sasl\n    local prefix\n    prefix="\$\(formula_prefix cyrus-sasl\)"\n    link_if_missing "\$\{prefix\}/include/sasl" "\$\{TP_INCLUDE_DIR\}/sasl"\n    link_matching_if_missing "\$\{TP_INSTALL_DIR\}/lib" "\$\{prefix\}/lib/libsasl2\.a" "\$\{prefix\}/lib/libsasl2\*\.dylib"\n    link_formula_metadata "\$\{prefix\}"\n    sync_lib64_links\n\}@build_formula_sasl() {\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        link_if_missing "${cyrus_sasl.dev}/include/sasl" "\$TP_INCLUDE_DIR/sasl"\n        link_matching_if_missing "\$TP_INSTALL_DIR/lib" "${cyrus_sasl.out}/lib/libsasl2*.dylib"\n        link_children_if_missing "${cyrus_sasl.out}/lib/sasl2" "\$TP_INSTALL_DIR/lib/sasl2"\n        link_formula_metadata "${cyrus_sasl.dev}"\n        sync_lib64_links\n        return 0\n    fi\n    ensure_formula cyrus-sasl\n    local prefix\n    prefix="\$(formula_prefix cyrus-sasl)"\n    link_if_missing "\''${prefix}/include/sasl" "\''${TP_INCLUDE_DIR}/sasl"\n    link_matching_if_missing "\''${TP_INSTALL_DIR}/lib" "\''${prefix}/lib/libsasl2.a" "\''${prefix}/lib/libsasl2*.dylib"\n    link_formula_metadata "\''${prefix}"\n    sync_lib64_links\n}@;
                    END { die "failed to patch Darwin cyrus-sasl staging\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_gperftools\(\) \{\n    ensure_formula gperftools\n    local prefix\n    prefix="\$\(formula_prefix gperftools\)"\n    link_if_missing "\$\{prefix\}" "\$\{TP_INSTALL_DIR\}/gperftools"\n    link_children_if_missing "\$\{prefix\}/include/gperftools" "\$\{TP_INCLUDE_DIR\}/gperftools"\n\}@build_formula_gperftools() {\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        mkdir -p "\$TP_INSTALL_DIR/gperftools/lib" "\$TP_INSTALL_DIR/gperftools/include/gperftools" "\$TP_INCLUDE_DIR/gperftools"\n        link_children_if_missing "${gperftools}/include/gperftools" "\$TP_INSTALL_DIR/gperftools/include/gperftools"\n        link_children_if_missing "${gperftools}/include/gperftools" "\$TP_INCLUDE_DIR/gperftools"\n        link_matching_if_missing "\$TP_INSTALL_DIR/gperftools/lib" "${gperftools}/lib/libprofiler.a" "${gperftools}/lib/libprofiler"*.dylib\n        link_matching_if_missing "\$TP_INSTALL_DIR/lib" "${gperftools}/lib/libprofiler.a" "${gperftools}/lib/libprofiler"*.dylib\n        if [[ ! -f "\$TP_INSTALL_DIR/gperftools/lib/libprofiler.a" ]]; then\n            echo "gperftools libprofiler.a missing after Nix staging"\n            exit 1\n        fi\n        if [[ ! -f "\$TP_INSTALL_DIR/gperftools/include/gperftools/profiler.h" ]]; then\n            echo "gperftools profiler.h missing after Nix staging"\n            exit 1\n        fi\n        sync_lib64_links\n        return 0\n    fi\n    ensure_formula gperftools\n    local prefix\n    prefix="\$(formula_prefix gperftools)"\n    link_if_missing "\''${prefix}" "\''${TP_INSTALL_DIR}/gperftools"\n    link_children_if_missing "\''${prefix}/include/gperftools" "\''${TP_INCLUDE_DIR}/gperftools"\n}@;
                    END { die "failed to patch Darwin gperftools staging\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@build_formula_ragel\(\) \{\n    ensure_formula ragel\n    local prefix\n    prefix="\$\(formula_prefix ragel\)"\n    link_matching_if_missing "\$\{TP_INSTALL_DIR\}/bin" "\$\{prefix\}/bin/ragel"\n\}@build_formula_ragel() {\n    if [[ "\$STARROCKS_USE_NIX_DEPS" == "1" ]]; then\n        if [[ -x "\$TP_INSTALL_DIR/bin/ragel" ]]; then\n            return 0\n        fi\n        check_if_source_exist "\$RAGEL_SOURCE"\n        cd "\$TP_SOURCE_DIR/\$RAGEL_SOURCE"\n        touch aclocal.m4 configure\n        find . -name Makefile.in -exec touch {} +\n        touch ragel/rlparse.cpp ragel/rlparse.h ragel/rlscan.cpp\n        if [[ -f Makefile ]]; then\n            make distclean >/dev/null 2>&1 || true\n        fi\n        ./configure --prefix="\$TP_INSTALL_DIR" --disable-shared --enable-static \\\n            CC="\$CC" CXX="\$CXX" CPPFLAGS="\$CPPFLAGS" CFLAGS="\$CFLAGS" CXXFLAGS="\$CXXFLAGS"\n        make -j"\$PARALLEL"\n        make install\n        return 0\n    fi\n    ensure_formula ragel\n    local prefix\n    prefix="\$(formula_prefix ragel)"\n    link_matching_if_missing "\''${TP_INSTALL_DIR}/bin" "\''${prefix}/bin/ragel"\n}@;
                    END { die "failed to patch Darwin ragel source build\n" unless $replaced }
                  ' thirdparty/build-thirdparty-darwin.sh
                perl -0pi -e '
                  our $replaced;
                  $replaced += s@setup_build_environment\(\) \{\n    local base_formula\n\n    for base_formula in coreutils gnu-tar wget gnu-getopt autoconf automake libtool cmake ninja bison pkg-config llvm; do\n        ensure_formula "\$\{base_formula\}"\n    done\n\n    export HOMEBREW_PREFIX=.*?\n    export STARROCKS_LLVM_HOME=.*?\n    export PATH=".*?"@setup_build_environment() {\n    export HOMEBREW_PREFIX="\''${HOMEBREW_PREFIX:-/opt/homebrew}"\n    export STARROCKS_LLVM_HOME="\''${STARROCKS_LLVM_HOME:-${llvmPackages.llvm}}"\n    export PATH="${
                    lib.makeBinPath [
                      coreutils
                      gnutar
                      wget
                      autoconf
                      automake
                      libtool
                      cmake
                      ninja
                      bison
                      pkg-config
                      llvmPackages.llvm
                    ]
                  }:\''${PATH}:/usr/bin:/usr/sbin:/bin:/sbin"@s;
                  END { die "failed to patch Darwin setup_build_environment\n" unless $replaced }
                ' thirdparty/build-thirdparty-darwin.sh
                perl -0pi -e '
                  our $replaced;
                  $replaced += s@if ! command -v brew >/dev/null 2>&1; then\n    echo "Homebrew is required on macOS"\n    exit 1\nfi@:@;
                  END { die "failed to patch Darwin Homebrew requirement\n" unless $replaced }
                ' thirdparty/build-thirdparty-darwin.sh
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail 'export AR="''${AR:-''${STARROCKS_LLVM_HOME}/bin/llvm-ar}"' 'export AR="${darwinArWrapper}"' \
                    --replace-fail 'export RANLIB="''${RANLIB:-''${STARROCKS_LLVM_HOME}/bin/llvm-ranlib}"' 'export RANLIB="${darwinRanlibWrapper}"'
                  substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                    --replace-fail 'rapidjson_prefix="$(formula_prefix rapidjson)"' 'if [[ "$STARROCKS_USE_NIX_DEPS" == "1" ]]; then
                rapidjson_prefix="$TP_INSTALL_DIR"
                if [[ ! -f "$rapidjson_prefix/include/rapidjson/rapidjson.h" ]]; then
                    echo "RapidJSON header missing before Arrow configure: $rapidjson_prefix/include/rapidjson/rapidjson.h"
                    exit 1
                fi
            else
                rapidjson_prefix="$(formula_prefix rapidjson)"
            fi'
                perl -0pi -e '
                  our $replaced;
                    $replaced += s#for package in "\$\{packages\[@\]\}"; do\n    if \[\[ "\$\{package\}" == "\$\{start_package\}" \]\]; then#for package in "\''${packages[@]}"; do\n    echo "===== begin Darwin thirdparty package: \$package"\n    if [[ "\$package" == "\$start_package" ]]; then#;
                  END { die "failed to patch Darwin package progress marker\n" unless $replaced }
                ' thirdparty/build-thirdparty-darwin.sh
              perl -0pi -e '
                our $replaced;
                $replaced += s@check_if_source_exist "\$\{HYPERSCAN_SOURCE\}"\n    cd "\$\{TP_SOURCE_DIR\}/\$\{HYPERSCAN_SOURCE\}"\n    rm -rf cmake_build@check_if_source_exist "\$HYPERSCAN_SOURCE"\n    export PATH="\$TP_INSTALL_DIR/bin:\$PATH"\n    cd "\$TP_SOURCE_DIR/\$HYPERSCAN_SOURCE"\n    rm -rf cmake_build@;
                END { die "failed to patch Darwin Hyperscan PATH\n" unless $replaced }
              ' thirdparty/build-thirdparty-darwin.sh
              perl -0pi -e '
                our $replaced;
                $replaced += s@    "\$\{OBJCOPY\}" --localize-symbol=cnd_timedwait "\$\{TP_INSTALL_DIR\}/lib/libserdes\.a"\n    "\$\{OBJCOPY\}" --localize-symbol=cnd_timedwait_ms "\$\{TP_INSTALL_DIR\}/lib/libserdes\.a"\n    "\$\{OBJCOPY\}" --localize-symbol=thrd_is_current "\$\{TP_INSTALL_DIR\}/lib/libserdes\.a"@    if [[ "\$STARROCKS_USE_NIX_DEPS" != "1" ]]; then\n        "\$OBJCOPY" --localize-symbol=cnd_timedwait "\$TP_INSTALL_DIR/lib/libserdes.a"\n        "\$OBJCOPY" --localize-symbol=cnd_timedwait_ms "\$TP_INSTALL_DIR/lib/libserdes.a"\n        "\$OBJCOPY" --localize-symbol=thrd_is_current "\$TP_INSTALL_DIR/lib/libserdes.a"\n    fi@;
                END { die "failed to patch Darwin serdes objcopy\n" unless $replaced }
              ' thirdparty/build-thirdparty-darwin.sh
                substituteInPlace thirdparty/build-thirdparty-darwin.sh \
                  --replace-fail '        -DRapidJSON_ROOT="''${rapidjson_prefix}" \' '        -DRapidJSON_ROOT="''${rapidjson_prefix}" \
              -DRapidJSON_SOURCE=SYSTEM \'
                  perl -0pi -e '
                    our $replaced;
                    $replaced += s@LDFLAGS="-L\$\{TP_INSTALL_DIR\}/lib" \\\n        LIBDIR="lib" \\\n        \./Configure@AR="/usr/bin/libtool" \\\n        RANLIB="/usr/bin/true" \\\n        LDFLAGS="-L\$\{TP_INSTALL_DIR\}/lib" \\\n        LIBDIR="lib" \\\n        ./Configure@;
                    $replaced += s@make -j"\$\{PARALLEL\}"\n    make install_sw@make -j"\$\{PARALLEL\}" AR="/usr/bin/libtool" ARFLAGS="-static -o" RANLIB="/usr/bin/true"\n    make install_sw AR="/usr/bin/libtool" ARFLAGS="-static -o" RANLIB="/usr/bin/true"@;
                    $replaced += s@darwin64-arm64-cc\n    make -j"\$\{PARALLEL\}" AR="/usr/bin/libtool" ARFLAGS="-static -o" RANLIB="/usr/bin/true"@darwin64-arm64-cc\n    perl -0pi -e "s|^AR=.*|AR=/usr/bin/libtool|m; s|^RANLIB=.*|RANLIB=/usr/bin/true|m; s|^ARFLAGS=.*|ARFLAGS=-static -o|m" Makefile\n    grep -Fq "/usr/bin/libtool" Makefile\n    grep -Fq "/usr/bin/true" Makefile\n    grep -Fq "ARFLAGS=-static -o" Makefile\n    make -j"\$\{PARALLEL\}" AR="/usr/bin/libtool" ARFLAGS="-static -o" RANLIB="/usr/bin/true"@;
                    END { die "failed to patch Darwin OpenSSL archive tools\n" unless $replaced == 3 }
                  ' thirdparty/build-thirdparty-darwin.sh
    ''}
    ${lib.optionalString isLinux ''
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
          substituteInPlace thirdparty/build-thirdparty.sh \
            --replace-fail '    ''${BUILD_SYSTEM} -j$PARALLEL
          ''${BUILD_SYSTEM} install
      }

      #mariadb-connector-c' '    ''${BUILD_SYSTEM} -j$PARALLEL
          rm -rf "$TP_INSTALL_DIR/include/hs"
          mkdir -p "$TP_INSTALL_DIR/include/hs"
          ''${BUILD_SYSTEM} install
      }

      #mariadb-connector-c'
    ''}

    export STARROCKS_HOME=$PWD
    export STARROCKS_GCC_HOME=${stdenv.cc}
    export CUSTOM_CMAKE=${cmakeWithPolicy}
    export JAVA_HOME=${jdk}
    export PARALLEL=${if isDarwin then "6" else linuxParallel}
    export THIRD_PARTY_BUILD_WITH_AVX2=OFF

    ./thirdparty/build-thirdparty.sh

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R thirdparty/installed $out/installed
    ${lib.optionalString isDarwin ''
      while IFS= read -r -d "" archive; do
        tmpdir="$(mktemp -d)"
        fixed="$tmpdir/$(basename "$archive")"
        if ! /usr/bin/libtool -static -o "$fixed" "$archive"; then
          echo "Darwin archive normalization failed for $archive"
          exit 1
        fi
        members="$tmpdir/members"
        if ! /usr/bin/ar -t "$fixed" > "$members"; then
          echo "Darwin archive inspection failed for $archive"
          exit 1
        fi
        first_member="$(sed -n '1p' "$members")"
        if [[ -z "$first_member" || "$first_member" == "__.SYMDEF" ]]; then
          echo "Darwin archive normalization failed for $archive"
          exit 1
        fi
        mv "$fixed" "$archive"
        rm -rf "$tmpdir"
      done < <(find "$out/installed/lib" -maxdepth 1 -type f -name 'libboost_*.a' -print0)
    ''}
    while IFS= read -r -d "" link; do
      target=$(readlink "$link")
      case "$target" in
        "$PWD/thirdparty/installed/"*)
          targetInOut="$out/installed/''${target#"$PWD/thirdparty/installed/"}"
          ln -sfn "$(realpath --relative-to="$(dirname "$link")" "$targetInOut")" "$link"
          ;;
      esac
    done < <(find "$out/installed" -type l -print0)
    while IFS= read -r -d "" link; do
      if [[ ! -e "$link" ]]; then
        rm -f "$link"
      fi
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
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
