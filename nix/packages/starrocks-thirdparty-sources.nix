{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
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
    }
    .${system}
      or (throw "StarRocks third-party source vendoring is supported only on Linux, got ${system}");

  hashes = {
    x86_64-linux = "sha256-z//aFgdHc54bRO/C6i3TDkKNyJxytLscsdGvglESNBc=";
    aarch64-linux = lib.fakeHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "starrocks-thirdparty-sources";
  version = release.version;

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
    ];
  };
}
