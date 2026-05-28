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
    owner = "StarRocks";
    repo = "starrocks";
    inherit (release) rev;
    hash = release.sourceHash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
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
    makeWrapper
    maven
    ninja
    jdk
    patch
    perl
    pkg-config
    procps
    protobuf
    python3
    thrift
    unzip
    util-linux
    wget
    which
    xz
    zip
  ];

  buildInputs = [
    libaio
    libxcrypt
    ncurses
    jdk
    openssl
    stdenv.cc.cc.lib
    zlib
    zstd
  ];

  postPatch = ''
    patchShebangs .
    substituteInPlace build.sh \
      --replace-fail 'FE_MODULES="hive-udf,fe-common,spark-dpp,fe-core"' 'FE_MODULES="fe-common,fe-core"' \
      --replace-fail 'cp -r -p ''${STARROCKS_HOME}/fe/spark-dpp/target/spark-dpp-*-jar-with-dependencies.jar ''${STARROCKS_OUTPUT}/fe/spark-dpp/' 'true # Spark DPP is not part of the Nix FE/BE server package.' \
      --replace-fail 'cp -r -p ''${STARROCKS_HOME}/fe/hive-udf/target/hive-udf-1.0.0.jar ''${STARROCKS_OUTPUT}/fe/hive-udf/' 'true # Hive UDF is not part of the Nix FE/BE server package.'
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"

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
    export CUSTOM_MVN="mvn -o -nsu -Djacoco.skip=true -Dmaven.javadoc.skip=true -Dmaven.repo.local=$PWD/.m2"
    export PARALLEL=''${NIX_BUILD_CORES:-1}

    export ENABLE_JIT=OFF
    export USE_AVX2=OFF
    export USE_AVX512=OFF
    export USE_BMI_2=OFF
    export USE_SSE4_2=OFF

    ./build.sh \
      --fe \
      --be \
      --without-avx2 \
      --without-tenann \
      --without-starcache \
      --without-java-ext \
      --disable-java-check-style \
      --with-maven-batch-mode ON

    runHook postBuild
  '';

  installPhase =
    let
      runtimePath = lib.makeBinPath [
        bash
        coreutils
        findutils
        gawk
        gnugrep
        gnused
        jdk
        procps
        util-linux
      ];
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
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
