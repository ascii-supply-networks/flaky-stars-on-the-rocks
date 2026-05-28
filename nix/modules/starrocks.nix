{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.starrocks;
  types = lib.types;

  scalarType = types.oneOf [
    types.bool
    types.int
    types.path
    types.str
  ];

  formatValue = value: if lib.isBool value then lib.boolToString value else toString value;

  mkStarRocksConf =
    settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name} = ${formatValue value}") settings
    )
    + "\n";

  feStateDir = "/var/lib/starrocks/fe";

  feBaseSettings = {
    sys_log_level = "INFO";
    http_port = 8030;
    rpc_port = 9020;
    query_port = 9030;
    edit_log_port = 9010;
    mysql_service_nio_enabled = true;
    meta_dir = "${feStateDir}/meta";
    sys_log_dir = "${feStateDir}/log";
    audit_log_dir = "${feStateDir}/log";
  };

  feSettings = feBaseSettings // cfg.fe.settings;

  feConfigFile = pkgs.writeText "starrocks-fe.conf" ''
    LOG_DIR = ${feStateDir}/log
    DATE = "$(date +%Y%m%d-%H%M%S)"
    JAVA_OPTS="${cfg.fe.javaOpts}"

    ${mkStarRocksConf feSettings}
  '';

  commonServicePath = with pkgs; [
    bash
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    procps
    util-linux
  ];

  enabledBackends = lib.filterAttrs (_name: backend: backend.enable) cfg.be.instances;
  activeBackends = lib.optionalAttrs cfg.be.enable enabledBackends;

  beStateDir = name: "/var/lib/starrocks/be-${name}";

  beConfigFile =
    name: backend:
    pkgs.writeText "starrocks-be-${name}.conf" (
      mkStarRocksConf (
        {
          sys_log_level = "INFO";
          be_port = backend.bePort;
          be_http_port = backend.httpPort;
          heartbeat_service_port = backend.heartbeatPort;
          brpc_port = backend.brpcPort;
          starlet_port = backend.starletPort;
          storage_root_path = "${beStateDir name}/storage";
          sys_log_dir = "${beStateDir name}/log";
        }
        // backend.settings
      )
    );

  registerBackendScript =
    name: backend:
    let
      mysql = "${cfg.mysqlClient}/bin/mysql";
      feQueryPort = toString backend.feQueryPort;
      heartbeatPort = toString backend.heartbeatPort;
    in
    ''
      show_backends() {
        ${mysql} --connect-timeout=2 -h ${lib.escapeShellArg backend.feHost} -P ${feQueryPort} -uroot --skip-column-names --batch -e 'SHOW BACKENDS;'
      }

      backend_registered() {
        show_backends | grep -F ${lib.escapeShellArg backend.advertiseHost} | grep -F ${lib.escapeShellArg heartbeatPort} >/dev/null
      }

      for attempt in $(seq 1 ${toString backend.registrationAttempts}); do
        if ${mysql} --connect-timeout=2 -h ${lib.escapeShellArg backend.feHost} -P ${feQueryPort} -uroot -e 'SELECT 1;' >/dev/null 2>&1; then
          break
        fi

        if [[ "$attempt" -eq ${toString backend.registrationAttempts} ]]; then
          echo "StarRocks FE ${backend.feHost}:${feQueryPort} did not become queryable" >&2
          exit 1
        fi

        sleep ${toString backend.registrationIntervalSeconds}
      done

      if ! backend_registered; then
        ${mysql} --connect-timeout=2 -h ${lib.escapeShellArg backend.feHost} -P ${feQueryPort} -uroot \
          -e 'ALTER SYSTEM ADD BACKEND "${backend.advertiseHost}:${heartbeatPort}";' || true
      fi

      for attempt in $(seq 1 ${toString backend.registrationAttempts}); do
        if backend_registered; then
          exit 0
        fi

        if [[ "$attempt" -eq ${toString backend.registrationAttempts} ]]; then
          echo "StarRocks BE ${backend.advertiseHost}:${heartbeatPort} was not visible in SHOW BACKENDS" >&2
          exit 1
        fi

        sleep ${toString backend.registrationIntervalSeconds}
      done
    '';

  mkBackendService =
    name: backend:
    let
      stateDir = beStateDir name;
    in
    lib.nameValuePair "starrocks-be-${name}" {
      description = "StarRocks backend ${name}";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ lib.optionals cfg.fe.enable [ "starrocks-fe.service" ];

      path = commonServicePath ++ [ cfg.mysqlClient ];

      preStart = ''
        ${cfg.package}/bin/starrocks-prepare-runtime be ${stateDir}
        mkdir -p ${stateDir}/log ${stateDir}/storage
        install -m 0644 ${beConfigFile name backend} ${stateDir}/home/conf/be.conf

        ${registerBackendScript name backend}
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "starrocks/be-${name}";
        WorkingDirectory = "${stateDir}/home";
        Environment = [
          "JAVA_HOME=${cfg.jdk}"
          "LOG_CONSOLE=1"
        ];
        ExecStart = "${stateDir}/home/bin/start_be.sh --be --logconsole";
        LimitNOFILE = 65535;
        Restart = "on-failure";
        TimeoutStartSec = "infinity";
      };
    };
in
{
  options.services.starrocks = {
    enable = lib.mkEnableOption "StarRocks FE/BE services";

    package = lib.mkOption {
      type = types.package;
      default = pkgs.starrocks or (pkgs.callPackage ../packages/starrocks.nix { });
      defaultText = lib.literalExpression "pkgs.starrocks";
      description = "StarRocks package to run.";
    };

    jdk = lib.mkOption {
      type = types.package;
      default = pkgs.openjdk21;
      defaultText = lib.literalExpression "pkgs.openjdk21";
      description = "JDK used by StarRocks FE and BE processes.";
    };

    mysqlClient = lib.mkOption {
      type = types.package;
      default = pkgs.mariadb.client;
      defaultText = lib.literalExpression "pkgs.mariadb.client";
      description = "MySQL-compatible client used to register BE nodes with FE.";
    };

    user = lib.mkOption {
      type = types.str;
      default = "starrocks";
      description = "User that owns and runs StarRocks state.";
    };

    group = lib.mkOption {
      type = types.str;
      default = "starrocks";
      description = "Group that owns and runs StarRocks state.";
    };

    openFirewall = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Open FE and BE TCP ports in the NixOS firewall.";
    };

    fe = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Run a StarRocks frontend service on this host.";
      };

      hostType = lib.mkOption {
        type = types.enum [
          "IP"
          "FQDN"
        ];
        default = "FQDN";
        description = "Address type passed to start_fe.sh.";
      };

      helper = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "starrocks-fe-0:9010";
        description = "Optional FE helper in host:edit_log_port form for follower FE startup.";
      };

      javaOpts = lib.mkOption {
        type = types.str;
        default = "-Dlog4j2.formatMsgNoLookups=true -Xmx1024m -XX:+UseG1GC -XX:ErrorFile=${feStateDir}/log/hs_err_pid%p.log -Djava.security.policy=${feStateDir}/home/conf/udf_security.policy";
        description = "JAVA_OPTS exported into fe.conf.";
      };

      settings = lib.mkOption {
        type = types.attrsOf scalarType;
        default = { };
        example = lib.literalExpression ''
          {
            query_port = 9031;
            priority_networks = "10.10.10.0/24";
          }
        '';
        description = "Additional or overriding StarRocks fe.conf settings.";
      };
    };

    be = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Run StarRocks backend services on this host.";
      };

      instances = lib.mkOption {
        type = types.attrsOf (
          types.submodule (
            { ... }:
            {
              options = {
                enable = lib.mkOption {
                  type = types.bool;
                  default = true;
                  description = "Run this backend instance.";
                };

                feHost = lib.mkOption {
                  type = types.str;
                  default = "127.0.0.1";
                  description = "FE host used for MySQL registration.";
                };

                feQueryPort = lib.mkOption {
                  type = types.port;
                  default = 9030;
                  description = "FE MySQL query port used for registration.";
                };

                advertiseHost = lib.mkOption {
                  type = types.str;
                  default = "127.0.0.1";
                  description = "Host registered with FE for this BE heartbeat endpoint.";
                };

                bePort = lib.mkOption {
                  type = types.port;
                  default = 9060;
                  description = "BE thrift server port.";
                };

                httpPort = lib.mkOption {
                  type = types.port;
                  default = 8040;
                  description = "BE HTTP server port.";
                };

                heartbeatPort = lib.mkOption {
                  type = types.port;
                  default = 9050;
                  description = "BE heartbeat service port registered with FE.";
                };

                brpcPort = lib.mkOption {
                  type = types.port;
                  default = 8060;
                  description = "BE bRPC port.";
                };

                starletPort = lib.mkOption {
                  type = types.port;
                  default = 9070;
                  description = "BE starlet port.";
                };

                registrationAttempts = lib.mkOption {
                  type = types.ints.positive;
                  default = 60;
                  description = "Number of attempts to wait for FE and BE registration.";
                };

                registrationIntervalSeconds = lib.mkOption {
                  type = types.ints.positive;
                  default = 2;
                  description = "Sleep interval between BE registration attempts.";
                };

                settings = lib.mkOption {
                  type = types.attrsOf scalarType;
                  default = { };
                  example = lib.literalExpression ''
                    {
                      priority_networks = "10.10.10.0/24";
                    }
                  '';
                  description = "Additional or overriding StarRocks be.conf settings.";
                };
              };
            }
          )
        );
        default = {
          "0" = { };
        };
        description = "Backend instances to run on this host.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.fe.enable || activeBackends != { };
            message = "services.starrocks must enable FE or at least one BE instance.";
          }
        ];

        users.users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          description = "StarRocks service user";
        };

        users.groups.${cfg.group} = { };
      }

      (lib.mkIf cfg.fe.enable {
        systemd.services.starrocks-fe = {
          description = "StarRocks frontend";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          path = commonServicePath;

          preStart = ''
            ${cfg.package}/bin/starrocks-prepare-runtime fe ${feStateDir}
            mkdir -p ${feStateDir}/log ${feStateDir}/meta
            install -m 0644 ${feConfigFile} ${feStateDir}/home/conf/fe.conf
          '';

          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = "starrocks/fe";
            WorkingDirectory = "${feStateDir}/home";
            Environment = [
              "JAVA_HOME=${cfg.jdk}"
              "SYS_LOG_TO_CONSOLE=1"
            ];
            ExecStart =
              "${feStateDir}/home/bin/start_fe.sh "
              + lib.escapeShellArgs (
                [
                  "--host_type"
                  cfg.fe.hostType
                  "--logconsole"
                ]
                ++ lib.optionals (cfg.fe.helper != null) [
                  "--helper"
                  cfg.fe.helper
                ]
              );
            LimitNOFILE = 65535;
            Restart = "on-failure";
            TimeoutStartSec = "infinity";
          };
        };
      })

      (lib.mkIf cfg.be.enable {
        systemd.services = lib.mapAttrs' mkBackendService activeBackends;
      })

      (lib.mkIf cfg.openFirewall {
        networking.firewall.allowedTCPPorts =
          lib.optionals cfg.fe.enable [
            feSettings.http_port
            feSettings.rpc_port
            feSettings.query_port
            feSettings.edit_log_port
          ]
          ++ lib.flatten (
            lib.mapAttrsToList (_name: backend: [
              backend.bePort
              backend.httpPort
              backend.heartbeatPort
              backend.brpcPort
              backend.starletPort
            ]) activeBackends
          );
      })
    ]
  );
}
