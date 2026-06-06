{
  lib,
  stdenv,
  fetchFromGitHub,
  callPackage,
  autoPatchelfHook,
  makeWrapper,
  autoconf,
  automake,
  bash,
  binutils,
  bison,
  bzip2,
  byacc,
  cmake,
  coreutils,
  curl,
  findutils,
  flex,
  gawk,
  gettext,
  getopt,
  gnumake,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  icu,
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
  procps,
  protobuf,
  python3,
  thrift,
  unzip,
  util-linux,
  wget,
  which,
  xz,
  zip,
  libaio,
  libiberty,
  libxcrypt,
  ncurses,
  openssl,
  zlib,
  zstd,
  starrocks-thirdparty ? callPackage ./starrocks-thirdparty.nix { inherit jdk; },
  starrocks-maven-repository ? callPackage ./starrocks-maven-repository.nix { inherit jdk; },
}:

let
  release = import ../starrocks-release.nix;
  isDarwin = stdenv.hostPlatform.isDarwin;
  isLinux = stdenv.hostPlatform.isLinux;
  linuxParallel = "\${NIX_BUILD_CORES:-1}";
  setupMavenJavaHome = ''
    real_java_home="$(${jdk}/bin/java -XshowSettings:properties -version 2>&1 | sed -n 's/^[[:space:]]*java.home = //p')"
    fake_java_parent="$TMPDIR/fake-java"
    fake_java_home="$fake_java_parent/Home"
    empty_tools_dir="$TMPDIR/empty-tools-jar"

    mkdir -p "$fake_java_home" "$fake_java_home/lib" "$fake_java_parent/lib" "$empty_tools_dir"

    for entry in "$real_java_home"/*; do
      base="$(basename "$entry")"
      if [ "$base" = "lib" ]; then
        continue
      fi
      ln -s "$entry" "$fake_java_home/$base"
    done

    for entry in "$real_java_home"/lib/*; do
      ln -s "$entry" "$fake_java_home/lib/$(basename "$entry")"
    done

    ${jdk}/bin/jar --create --file "$fake_java_parent/lib/tools.jar" -C "$empty_tools_dir" .
    ln -s "$fake_java_parent/lib/tools.jar" "$fake_java_home/lib/tools.jar"

    export JAVA_HOME="$fake_java_home"
    export MAVEN_OPTS="''${MAVEN_OPTS:-} -Djava.home=$fake_java_home"
  '';
in
stdenv.mkDerivation {
  pname = "starrocks";
  version = release.version;

  src = fetchFromGitHub {
    owner = release.sourceOwner;
    repo = release.sourceRepo;
    inherit (release) rev;
    hash = release.sourceHash;
  };

  nativeBuildInputs =
    lib.optionals isLinux [
      autoPatchelfHook
      procps
      util-linux
    ]
    ++ [
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
      getopt
      gnumake
      gnugrep
      gnused
      gnutar
      gzip
      libtool
      makeWrapper
      maven
      ninja
      jdk
      patch
      perl
      pkg-config
      protobuf
      python3
      thrift
      unzip
      wget
      which
      xz
      zip
    ];

  buildInputs =
    lib.optionals isLinux [
      libaio
      libiberty
      libxcrypt
    ]
    ++ [
      ncurses
      jdk
      openssl
      stdenv.cc.cc.lib
      zlib
      zstd
    ];

  __noChroot = isDarwin;

  dontConfigure = true;

  postPatch = ''
        patchShebangs .
        substituteInPlace be/src/base/hash/hash.h \
          --replace-fail '#include <cstdint>' '#include <cstdint>
        #include <zlib.h>'
        substituteInPlace be/src/gutil/port.h \
          --replace-fail '// define the macros IS_LITTLE_ENDIAN or IS_BIG_ENDIAN
    // using the above endian defintions from endian.h if
    // endian.h was included
    #ifdef __BYTE_ORDER
    #if __BYTE_ORDER == __LITTLE_ENDIAN
    #define IS_LITTLE_ENDIAN
    #endif

    #if __BYTE_ORDER == __BIG_ENDIAN
    #define IS_BIG_ENDIAN
    #endif

    #else

    #if defined(__LITTLE_ENDIAN__)
    #define IS_LITTLE_ENDIAN
    #elif defined(__BIG_ENDIAN__)
    #define IS_BIG_ENDIAN
    #endif

    // there is also PDP endian ...

    #endif // __BYTE_ORDER' '// define the macros IS_LITTLE_ENDIAN or IS_BIG_ENDIAN.
    // Some third-party headers, including CRoaring, also define these names. Keep
    // StarRocks marker semantics by clearing inherited definitions before setting
    // the byte-order marker for this translation unit.
    #undef IS_LITTLE_ENDIAN
    #undef IS_BIG_ENDIAN

    #if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    #define IS_LITTLE_ENDIAN
    #elif defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
    #define IS_BIG_ENDIAN
    #elif defined(__BYTE_ORDER) && defined(__LITTLE_ENDIAN) && (__BYTE_ORDER == __LITTLE_ENDIAN)
    #define IS_LITTLE_ENDIAN
    #elif defined(__BYTE_ORDER) && defined(__BIG_ENDIAN) && (__BYTE_ORDER == __BIG_ENDIAN)
    #define IS_BIG_ENDIAN
    #elif defined(__LITTLE_ENDIAN__)
    #define IS_LITTLE_ENDIAN
    #elif defined(__BIG_ENDIAN__)
    #define IS_BIG_ENDIAN
    #endif'
        substituteInPlace be/src/base/types/uint24.h \
          --replace-fail 'static_cast<uint>(*this) >> bits' 'static_cast<uint32_t>(*this) >> bits'
        substituteInPlace be/src/formats/parquet/parquet_file_writer.h \
          --replace-fail 'inline static std::string VERSION = "version";' 'inline static std::string VERSION_KEY = "version";'
        substituteInPlace be/src/formats/parquet/parquet_file_writer.cpp \
          --replace-fail 'ParquetWriterOptions::VERSION' 'ParquetWriterOptions::VERSION_KEY'
        substituteInPlace be/src/exec/data_sinks/table_function_table_sink.cpp \
          --replace-fail 'ParquetWriterOptions::VERSION' 'ParquetWriterOptions::VERSION_KEY'
        substituteInPlace be/src/service/CMakeLists.txt \
          --replace-fail '    target_link_libraries(starrocks_be
            ServiceBE
            Service
            ''${STARROCKS_LINK_LIBS}
            )
        STARROCKS_FORCE_LOAD_LIBS(starrocks_be Exprs ExprCore)' '    target_link_libraries(starrocks_be
            ServiceBE
            Service
            ''${STARROCKS_LINK_LIBS}
            )
        if (APPLE)
            # Darwin lacks GNU linker groups, and CMake appends some static target
            # dependencies after STARROCKS_LINK_LIBS. Force-load the Boost archives
            # that satisfy late Avro and RuntimeEnv references.
            target_link_options(starrocks_be PRIVATE
                "LINKER:-force_load,''${THIRDPARTY_DIR}/lib/libboost_thread.a"
                "LINKER:-force_load,''${THIRDPARTY_DIR}/lib/libboost_iostreams.a"
            )
            target_link_libraries(starrocks_be "${xz.out}/lib/liblzma.dylib")
        endif()
        STARROCKS_FORCE_LOAD_LIBS(starrocks_be Exprs ExprCore)'
        substituteInPlace build.sh \
          --replace-fail 'FE_MODULES="plugin/hive-udf,fe-testing,plugin/spark-dpp,fe-server"' 'FE_MODULES="fe-server"' \
          --replace-fail 'cp -r -p ''${STARROCKS_HOME}/fe/plugin/spark-dpp/target/spark-dpp-*-jar-with-dependencies.jar ''${STARROCKS_OUTPUT}/fe/spark-dpp/' 'true # Spark DPP is not part of the Nix FE/BE server package.' \
          --replace-fail 'cp -r -p ''${STARROCKS_HOME}/fe/plugin/hive-udf/target/hive-udf-*.jar ''${STARROCKS_OUTPUT}/fe/hive-udf/' 'true # Hive UDF is not part of the Nix FE/BE server package.'
        substituteInPlace build-support/darwin_build_env.sh \
          --replace-fail '# Parallel builds
    export PARALLEL="$(detect_parallelism)"
    export MAKEFLAGS="-j''${PARALLEL}"

    log_info "Parallel jobs: $PARALLEL"' '# Parallel builds
    if [[ -n "''${NIX_BUILD_CORES:-}" && "''${NIX_BUILD_CORES}" =~ ^[0-9]+$ && "''${NIX_BUILD_CORES}" -gt 0 ]]; then
        export PARALLEL="''${NIX_BUILD_CORES}"
    elif [[ -n "''${PARALLEL:-}" && "''${PARALLEL}" =~ ^[0-9]+$ && "''${PARALLEL}" -gt 0 ]]; then
        export PARALLEL
    else
        export PARALLEL="$(detect_parallelism)"
    fi
    export MAKEFLAGS="-j''${PARALLEL}"

    log_info "Parallel jobs: $PARALLEL"'
        for pom in \
          fe/fe-core/pom.xml \
          fe/fe-parser/pom.xml \
          fe/fe-testing/pom.xml \
          fe/plugin/spark-dpp/pom.xml \
          java-extensions/pom.xml
        do
          substituteInPlace "$pom" \
            --replace-fail '<phase>validate</phase>' '<phase>none</phase>'
        done
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    ${lib.optionalString isDarwin ''
      make_combined_root() {
        local root="$1"
        shift

        rm -rf "$root"
        mkdir -p "$root"

        for input in "$@"; do
          for dir in bin include lib share; do
            if [[ ! -d "$input/$dir" ]]; then
              continue
            fi
            mkdir -p "$root/$dir"
            for entry in "$input/$dir"/*; do
              [[ -e "$entry" ]] || continue
              ln -sfn "$entry" "$root/$dir/$(basename "$entry")"
            done
          done
        done
      }

      make_combined_root "$PWD/nix-openssl-root" "${openssl.dev}" "${openssl.out}"
      make_combined_root "$PWD/nix-curl-root" "${curl.dev}" "${curl.out}"
      make_combined_root "$PWD/nix-icu-root" "${icu.dev}" "${icu.out}"
      make_combined_root "$PWD/nix-pcre2-root" "${pcre2.dev}" "${pcre2.out}"

      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
      export HOMEBREW_NO_AUTO_UPDATE=1
      export STARROCKS_USE_NIX_DEPS=1
      export STARROCKS_LLVM_HOME=${llvmPackages.llvm}
      export LLVM_HOME=${llvmPackages.llvm}
      export OPENSSL_ROOT_DIR="$PWD/nix-openssl-root"
      export CURL_ROOT="$PWD/nix-curl-root"
      export ICU_ROOT="$PWD/nix-icu-root"
      export PCRE2_ROOT_DIR="$PWD/nix-pcre2-root"
    ''}

    cp -R ${starrocks-maven-repository}/.m2 .m2
    chmod -R u+w .m2

    export STARROCKS_HOME=$PWD
    export STARROCKS_VERSION=${release.version}
    export STARROCKS_COMMIT_HASH=${release.commitHash}
    export STARROCKS_THIRDPARTY=${starrocks-thirdparty}
    export STARROCKS_OUTPUT=$PWD/output
    export STARROCKS_GCC_HOME=${stdenv.cc}
    export CUSTOM_CMAKE=${cmake}/bin/cmake
    ${setupMavenJavaHome}
    export CUSTOM_MVN="mvn -o -nsu -Dcheckstyle.skip=true -Djacoco.skip=true -Dmaven.javadoc.skip=true -Dmaven.repo.local=$PWD/.m2"
    export PARALLEL=${if isDarwin then "6" else linuxParallel}

    export ENABLE_JIT=OFF
    export USE_AVX2=OFF
    export USE_AVX512=OFF
    export USE_BMI_2=OFF
    export USE_SSE4_2=OFF

    ./build.sh \
      --fe \
      --be \
      -j "$PARALLEL" \
      --without-avx2 \
      --without-tenann \
      --without-starcache \
      --without-java-ext \
      --without-pch \
      --disable-java-check-style \
      --with-maven-batch-mode ON

    runHook postBuild
  '';

  installPhase =
    let
      runtimePath =
        lib.makeBinPath [
          bash
          coreutils
          findutils
          gawk
          gnugrep
          gnused
          jdk
        ]
        + lib.optionalString isLinux (
          ":"
          + lib.makeBinPath [
            procps
            util-linux
          ]
        );
    in
    ''
      runHook preInstall

      mkdir -p $out/share/starrocks $out/bin
      cp -a output/fe output/be $out/share/starrocks/
      cp -a output/LICENSE.txt output/NOTICE.txt $out/share/starrocks/

      if [ -d output/apache_hdfs_broker ]; then
        cp -a output/apache_hdfs_broker $out/share/starrocks/
      fi

      chmod -R u+rwX $out/share/starrocks
      patchShebangs $out/share/starrocks
      rm -f $out/share/starrocks/be/lib/starrocks_be.debuginfo

      makeWrapper $out/share/starrocks/fe/bin/start_fe.sh $out/bin/starrocks-fe \
        --set-default JAVA_HOME ${jdk} \
        --prefix PATH : ${runtimePath}

      makeWrapper $out/share/starrocks/be/bin/start_be.sh $out/bin/starrocks-be \
        --set-default JAVA_HOME ${jdk} \
        --prefix PATH : ${runtimePath}

      cat > $out/bin/starrocks-prepare-runtime <<'EOF'
      #!${bash}/bin/bash
      set -euo pipefail

      component="''${1:?component is required}"
      state_dir="''${2:?state directory is required}"
      source_dir="@out@/share/starrocks/$component"
      home_dir="$state_dir/home"
      tmp_dir="$state_dir/.home.tmp"
      marker_file="$home_dir/.starrocks-source"

      if [[ "$component" != "fe" && "$component" != "be" ]]; then
        echo "unsupported StarRocks component: $component" >&2
        exit 64
      fi

      if [[ -f "$marker_file" ]] && [[ "$(cat "$marker_file")" == "$source_dir" ]]; then
        exit 0
      fi

      rm -rf "$tmp_dir"
      mkdir -p "$tmp_dir"

      copy_writable() {
        cp -a "$1" "$2"
        chmod -R u+rwX "$2"
      }

      link_top_level_except() {
        local skip=" $* "
        local entry
        local base

        for entry in "$source_dir"/*; do
          base="$(basename "$entry")"
          if [[ "$skip" == *" $base "* ]]; then
            continue
          fi
          ln -s "$entry" "$tmp_dir/$base"
        done
      }

      copy_writable "$source_dir/bin" "$tmp_dir/bin"
      copy_writable "$source_dir/conf" "$tmp_dir/conf"

      case "$component" in
        fe)
          link_top_level_except bin conf log meta
          ;;
        be)
          mkdir -p "$tmp_dir/lib"
          copy_writable "$source_dir/lib/starrocks_be" "$tmp_dir/lib/starrocks_be"
          for entry in "$source_dir"/lib/*; do
            base="$(basename "$entry")"
            if [[ "$base" == "starrocks_be" ]]; then
              continue
            fi
            ln -s "$entry" "$tmp_dir/lib/$base"
          done
          link_top_level_except bin conf lib log storage
          ;;
      esac

      printf '%s\n' "$source_dir" > "$tmp_dir/.starrocks-source"
      rm -rf "$home_dir"
      mv "$tmp_dir" "$home_dir"
      EOF

      substituteInPlace $out/bin/starrocks-prepare-runtime \
        --replace-fail "@out@" "$out"
      chmod +x $out/bin/starrocks-prepare-runtime

      runHook postInstall
    '';

  meta = {
    description = "StarRocks shared-nothing analytical database built from source";
    homepage = "https://www.starrocks.io/";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
