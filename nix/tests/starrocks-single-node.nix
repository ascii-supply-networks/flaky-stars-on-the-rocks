{
  pkgs,
  starrocksModule,
  starrocksPackage,
}:

pkgs.testers.nixosTest {
  name = "starrocks-single-node";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ starrocksModule ];

      services.starrocks = {
        enable = true;
        package = starrocksPackage;
        openFirewall = true;
      };

      environment.systemPackages = [ pkgs.mariadb.client ];

      system.stateVersion = "26.05";

      virtualisation = {
        diskSize = 16384;
        memorySize = 4096;
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("starrocks-fe.service")
    machine.wait_for_open_port(9030)
    machine.wait_for_unit("starrocks-be-0.service")
    machine.wait_for_open_port(8040)

    machine.wait_until_succeeds(
        "mysql -h 127.0.0.1 -P9030 -uroot --skip-column-names --batch -e 'SHOW BACKENDS;' | grep -F 9050"
    )

    machine.succeed("mysql -h 127.0.0.1 -P9030 -uroot -e 'CREATE DATABASE IF NOT EXISTS smoke;'")
    machine.succeed(
        "mysql -h 127.0.0.1 -P9030 -uroot -e 'CREATE TABLE IF NOT EXISTS smoke.demo (v INT) DUPLICATE KEY(v) DISTRIBUTED BY HASH(v) BUCKETS 1 PROPERTIES (\"replication_num\" = \"1\");'"
    )
    machine.succeed("mysql -h 127.0.0.1 -P9030 -uroot -e 'INSERT INTO smoke.demo VALUES (42);'")
    machine.succeed(
        "mysql -h 127.0.0.1 -P9030 -uroot --skip-column-names --batch -e 'SELECT v FROM smoke.demo;' | grep -F 42"
    )
  '';
}
