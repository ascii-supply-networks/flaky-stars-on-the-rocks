{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  cacert,
  coreutils,
  findutils,
  gnused,
  gnugrep,
  gawk,
  maven,
  openjdk21,
  jdk ? openjdk21,
  protobuf,
  thrift,
}:

let
  release = import ../starrocks-release.nix;
  system = stdenvNoCC.hostPlatform.system;
  hashes = {
    x86_64-linux = lib.fakeHash;
    aarch64-linux = lib.fakeHash;
  };
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
stdenvNoCC.mkDerivation {
  pname = "starrocks-maven-repository";
  version = release.version;

  src = fetchFromGitHub {
    owner = release.sourceOwner;
    repo = release.sourceRepo;
    inherit (release) rev;
    hash = release.sourceHash;
  };

  nativeBuildInputs = [
    cacert
    coreutils
    findutils
    gnused
    gnugrep
    gawk
    maven
    jdk
    protobuf
    thrift
  ];

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR/home
    mkdir -p "$HOME" "$out/.m2"
    ${setupMavenJavaHome}

    install_dummy_artifact() {
      local artifact="$1"
      local version="$2"
      local artifact_dir="$out/.m2/com/starrocks/$artifact/$version"

      mkdir -p "$artifact_dir"
      : > "$artifact_dir/$artifact-$version.jar"
      printf '%s\n' \
        '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
        '  <modelVersion>4.0.0</modelVersion>' \
        '  <groupId>com.starrocks</groupId>' \
        "  <artifactId>$artifact</artifactId>" \
        "  <version>$version</version>" \
        '</project>' \
        > "$artifact_dir/$artifact-$version.pom"
    }

    install_dummy_artifact plugin-common 1.0.0
    install_dummy_artifact fe-common 1.0.0
    install_dummy_artifact spark-dpp 1.0.0

    mvn_common=(
      -B
      -DskipTests
      -Dcheckstyle.skip=true
      -Djacoco.skip=true
      -Dmaven.javadoc.skip=true
      -Dmaven.repo.local="$out/.m2"
    )

    mvn "''${mvn_common[@]}" -f fe/pom.xml \
      -pl fe-server \
      -am \
      dependency:go-offline

    mvn "''${mvn_common[@]}" -f java-extensions/pom.xml \
      -pl hadoop-ext \
      -am \
      dependency:go-offline

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    find "$out/.m2" -type f \( \
      -name '*.lastUpdated' \
      -o -name resolver-status.properties \
      -o -name _remote.repositories \
    \) -delete

    runHook postInstall
  '';

  outputHashMode = "recursive";
  outputHash =
    hashes.${system}
      or (throw "StarRocks Maven repository vendoring is supported only on Linux, got ${system}");

  meta = {
    description = "Vendored Maven repository for native StarRocks builds";
    homepage = "https://github.com/StarRocks/starrocks";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
