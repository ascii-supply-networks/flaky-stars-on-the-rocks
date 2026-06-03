{
  lib,
  fetchFromGitHub,
  thrift,
}:

let
  dropCmakeFlag =
    flag:
    builtins.isString flag
    && lib.any (prefix: lib.hasPrefix prefix flag) [
      "-DBUILD_CPP"
      "-DBUILD_LIBRARIES"
      "-DBUILD_TESTING"
      "-DWITH_CPP"
      "-DWITH_OPENSSL"
    ];
in
thrift.overrideAttrs (old: {
  pname = "starrocks-thrift";
  version = "0.20.0";

  src = fetchFromGitHub {
    owner = "apache";
    repo = "thrift";
    tag = "v0.20.0";
    hash = "sha256-cwFTcaNHq8/JJcQxWSelwAGOLvZHoMmjGV3HBumgcWo=";
  };

  cmakeFlags = lib.filter (flag: !dropCmakeFlag flag) (old.cmakeFlags or [ ]) ++ [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DBUILD_LIBRARIES=OFF"
    "-DBUILD_CPP=OFF"
    "-DBUILD_TESTING=OFF"
    "-DWITH_CPP=OFF"
    "-DWITH_OPENSSL=OFF"
  ];

  doCheck = false;

  meta = old.meta // {
    description = "Apache Thrift compiler pinned to the version used by StarRocks";
  };
})
