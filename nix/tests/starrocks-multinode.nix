{
  pkgs,
  starrocksModule,
  starrocksPackage,
}:

let
  common =
    { pkgs, ... }:
    {
      imports = [ starrocksModule ];

      environment.systemPackages = [ pkgs.mariadb.client ];

      system.stateVersion = "26.05";

      virtualisation = {
        diskSize = 16384;
        memorySize = 4096;
      };
    };
in
pkgs.testers.nixosTest {
  name = "starrocks-multinode";

  nodes = {
    fe =
      { ... }:
      {
        imports = [ common ];

        networking.hostName = "fe";

        services.starrocks = {
          enable = true;
          package = starrocksPackage;
          openFirewall = true;
          be.enable = false;
        };
      };

    be1 =
      { ... }:
      {
        imports = [ common ];

        networking.hostName = "be1";

        services.starrocks = {
          enable = true;
          package = starrocksPackage;
          openFirewall = true;
          fe.enable = false;
          be.instances."0" = {
            feHost = "fe";
            advertiseHost = "be1";
          };
        };
      };

    be2 =
      { ... }:
      {
        imports = [ common ];

        networking.hostName = "be2";

        services.starrocks = {
          enable = true;
          package = starrocksPackage;
          openFirewall = true;
          fe.enable = false;
          be.instances."0" = {
            feHost = "fe";
            advertiseHost = "be2";
          };
        };
      };
  };

  testScript = ''
    fe.start()
    fe.wait_for_unit("starrocks-fe.service")
    fe.wait_for_open_port(9030)

    be1.start()
    be2.start()

    for backend in [be1, be2]:
        backend.wait_for_unit("starrocks-be-0.service")
        backend.wait_for_open_port(8040)

    fe.wait_until_succeeds(
        "mysql -h 127.0.0.1 -P9030 -uroot --skip-column-names --batch -e 'SHOW BACKENDS;' | grep -F be1 | grep -F 9050"
    )
    fe.wait_until_succeeds(
        "mysql -h 127.0.0.1 -P9030 -uroot --skip-column-names --batch -e 'SHOW BACKENDS;' | grep -F be2 | grep -F 9050"
    )

    fe.succeed("mysql -h 127.0.0.1 -P9030 -uroot -e 'CREATE DATABASE IF NOT EXISTS smoke;'")
    fe.succeed(
        "mysql -h 127.0.0.1 -P9030 -uroot -e 'CREATE TABLE IF NOT EXISTS smoke.demo (v INT) DUPLICATE KEY(v) DISTRIBUTED BY HASH(v) BUCKETS 1 PROPERTIES (\"replication_num\" = \"2\");'"
    )
    fe.succeed("mysql -h 127.0.0.1 -P9030 -uroot -e 'INSERT INTO smoke.demo VALUES (7);'")
    fe.succeed(
        "mysql -h 127.0.0.1 -P9030 -uroot --skip-column-names --batch -e 'SELECT v FROM smoke.demo;' | grep -F 7"
    )
  '';
}
