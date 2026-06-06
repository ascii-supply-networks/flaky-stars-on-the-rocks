{
  pkgs,
  starrocksPackage,
}:

pkgs.runCommand "starrocks-darwin-single-node"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      getopt
      gnugrep
      gnused
      mariadb.client
    ];

    __noChroot = pkgs.stdenv.hostPlatform.isDarwin;
    meta.platforms = [ "aarch64-darwin" ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export JAVA_HOME="${pkgs.openjdk21}"
    mkdir -p "$HOME"

    work="$TMPDIR/starrocks-darwin-single-node"
    fe_state="$work/fe"
    be_state="$work/be"
    fe_pid=""
    be_pid=""

    dump_logs() {
      echo "===== FE stdout =====" >&2
      tail -120 "$work/fe.stdout" >&2 || true
      echo "===== FE logs =====" >&2
      find "$fe_state/log" -maxdepth 1 -type f -print -exec tail -120 {} \; >&2 || true
      echo "===== BE stdout =====" >&2
      tail -160 "$work/be.stdout" >&2 || true
      echo "===== BE logs =====" >&2
      find "$be_state/log" -maxdepth 1 -type f -print -exec tail -160 {} \; >&2 || true
    }

    cleanup() {
      status=$?
      set +e
      if [ "$status" -ne 0 ]; then
        dump_logs
      fi
      if [ -n "$be_pid" ] && kill -0 "$be_pid" 2>/dev/null; then
        kill "$be_pid" 2>/dev/null || true
      fi
      if [ -n "$fe_pid" ] && kill -0 "$fe_pid" 2>/dev/null; then
        kill "$fe_pid" 2>/dev/null || true
      fi
      wait "$be_pid" 2>/dev/null || true
      wait "$fe_pid" 2>/dev/null || true
      exit "$status"
    }
    trap cleanup EXIT

    mysql_query() {
      mysql --connect-timeout=2 -h 127.0.0.1 -P19030 -uroot "$@"
    }

    wait_for_fe() {
      for attempt in $(seq 1 90); do
        if mysql_query -e 'SELECT 1;' >/dev/null 2>&1; then
          return 0
        fi
        if ! kill -0 "$fe_pid" 2>/dev/null; then
          echo "StarRocks FE exited before becoming queryable" >&2
          return 1
        fi
        sleep 2
      done

      echo "StarRocks FE did not become queryable" >&2
      return 1
    }

    wait_for_be_alive() {
      local backends

      for attempt in $(seq 1 120); do
        backends="$(mysql_query --skip-column-names --batch -e 'SHOW BACKENDS;' 2>/dev/null || true)"
        if printf '%s\n' "$backends" | grep -F 19050 | grep -F true >/dev/null; then
          return 0
        fi
        if ! kill -0 "$be_pid" 2>/dev/null; then
          echo "StarRocks BE exited before becoming alive" >&2
          printf '%s\n' "$backends" >&2
          return 1
        fi
        sleep 2
      done

      echo "StarRocks BE did not become alive" >&2
      mysql_query --skip-column-names --batch -e 'SHOW BACKENDS;' >&2 || true
      return 1
    }

    ${starrocksPackage}/bin/starrocks-prepare-runtime fe "$fe_state"
    mkdir -p "$fe_state/log" "$fe_state/meta"
    cat > "$fe_state/home/conf/fe.conf" <<EOF
    LOG_DIR = $fe_state/log
    DATE = "$(date +%Y%m%d-%H%M%S)"
    JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx1024m -XX:+UseG1GC -XX:ErrorFile=$fe_state/log/hs_err_pid%p.log -Djava.security.policy=$fe_state/home/conf/udf_security.policy"
    sys_log_level = INFO
    http_port = 18030
    rpc_port = 19020
    query_port = 19030
    edit_log_port = 19010
    mysql_service_nio_enabled = true
    meta_dir = $fe_state/meta
    sys_log_dir = $fe_state/log
    audit_log_dir = $fe_state/log
    priority_networks = 127.0.0.1/32
    EOF

    (
      cd "$fe_state/home"
      SYS_LOG_TO_CONSOLE=1 "$fe_state/home/bin/start_fe.sh" --host_type IP --logconsole > "$work/fe.stdout" 2>&1
    ) &
    fe_pid=$!

    wait_for_fe

    mysql_query -e 'ALTER SYSTEM ADD BACKEND "127.0.0.1:19050";' || true

    ${starrocksPackage}/bin/starrocks-prepare-runtime be "$be_state"
    mkdir -p "$be_state/log" "$be_state/storage"
    cat > "$be_state/home/conf/be.conf" <<EOF
    sys_log_level = INFO
    be_port = 19060
    be_http_port = 18040
    heartbeat_service_port = 19050
    brpc_port = 18060
    starlet_port = 19070
    storage_root_path = $be_state/storage
    sys_log_dir = $be_state/log
    priority_networks = 127.0.0.1/32
    JAVA_OPTS="--add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED"
    EOF

    (
      cd "$be_state/home"
      LOG_CONSOLE=1 "$be_state/home/bin/start_be.sh" --be --logconsole > "$work/be.stdout" 2>&1
    ) &
    be_pid=$!

    wait_for_be_alive

    mysql_query -e 'CREATE DATABASE IF NOT EXISTS smoke;'
    mysql_query -e 'CREATE TABLE IF NOT EXISTS smoke.demo (v INT) DUPLICATE KEY(v) DISTRIBUTED BY HASH(v) BUCKETS 1 PROPERTIES ("replication_num" = "1");'
    mysql_query -e 'INSERT INTO smoke.demo VALUES (42);'
    mysql_query --skip-column-names --batch -e 'SELECT v FROM smoke.demo;' | grep -F 42

    mkdir -p "$out"
    touch "$out/passed"
  ''
