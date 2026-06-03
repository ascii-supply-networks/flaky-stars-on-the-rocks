{
  fetchFromGitHub,
  thrift,
}:

thrift.overrideAttrs (old: {
  pname = "starrocks-thrift";
  version = "0.20.0";

  src = fetchFromGitHub {
    owner = "apache";
    repo = "thrift";
    tag = "v0.20.0";
    hash = "sha256-cwFTcaNHq8/JJcQxWSelwAGOLvZHoMmjGV3HBumgcWo=";
  };

  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DBUILD_TESTING=OFF"
  ];

  doCheck = false;

  meta = old.meta // {
    description = "Apache Thrift compiler pinned to the version used by StarRocks";
  };
})
