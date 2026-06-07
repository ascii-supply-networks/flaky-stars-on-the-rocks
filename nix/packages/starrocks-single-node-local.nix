{
  lib,
  stdenv,
  writeShellApplication,
  coreutils,
  findutils,
  gawk,
  getopt,
  gnugrep,
  gnused,
  mariadb,
  openjdk21,
  procps,
  starrocksPackage,
}:

writeShellApplication {
  name = "starrocks-single-node-local";

  runtimeInputs = [
    coreutils
    findutils
    gawk
    getopt
    gnugrep
    gnused
    mariadb.client
    openjdk21
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ procps ];

  text = ''
    set -euo pipefail

    log() {
      printf '%s\n' "$*"
    }

    fail() {
      printf 'starrocks-single-node-local: %s\n' "$*" >&2
      exit 1
    }

    require_uint() {
      local name="$1"
      local value="$2"

      case "$value" in
        "" | *[!0-9]*)
          fail "$name must be an unsigned integer, got: $value"
          ;;
      esac
    }

    default_state_parent="''${XDG_STATE_HOME:-''${HOME:-$PWD}/.local/state}"
    state_dir="''${STARROCKS_STATE_DIR:-$default_state_parent/starrocks-single-node-local}"
    state_dir="''${state_dir%/}"

    host="''${STARROCKS_HOST:-127.0.0.1}"
    advertise_host="''${STARROCKS_ADVERTISE_HOST:-$host}"
    database="''${STARROCKS_DATABASE:-metaxy}"
    case "$database" in
      "" | *[!A-Za-z0-9_]*)
        fail "STARROCKS_DATABASE must contain only letters, digits, and underscores, got: $database"
        ;;
    esac

    fe_http_port="''${STARROCKS_FE_HTTP_PORT:-8030}"
    fe_rpc_port="''${STARROCKS_FE_RPC_PORT:-9020}"
    query_port="''${STARROCKS_QUERY_PORT:-9030}"
    fe_edit_log_port="''${STARROCKS_FE_EDIT_LOG_PORT:-9010}"
    be_port="''${STARROCKS_BE_PORT:-9060}"
    be_http_port="''${STARROCKS_BE_HTTP_PORT:-8040}"
    be_heartbeat_port="''${STARROCKS_BE_HEARTBEAT_PORT:-''${STARROCKS_HEARTBEAT_PORT:-9050}}"
    be_brpc_port="''${STARROCKS_BE_BRPC_PORT:-8060}"
    be_starlet_port="''${STARROCKS_BE_STARLET_PORT:-9070}"
    wait_attempts="''${STARROCKS_WAIT_ATTEMPTS:-120}"
    wait_interval_seconds="''${STARROCKS_WAIT_INTERVAL_SECONDS:-2}"

    require_uint STARROCKS_FE_HTTP_PORT "$fe_http_port"
    require_uint STARROCKS_FE_RPC_PORT "$fe_rpc_port"
    require_uint STARROCKS_QUERY_PORT "$query_port"
    require_uint STARROCKS_FE_EDIT_LOG_PORT "$fe_edit_log_port"
    require_uint STARROCKS_BE_PORT "$be_port"
    require_uint STARROCKS_BE_HTTP_PORT "$be_http_port"
    require_uint STARROCKS_BE_HEARTBEAT_PORT "$be_heartbeat_port"
    require_uint STARROCKS_BE_BRPC_PORT "$be_brpc_port"
    require_uint STARROCKS_BE_STARLET_PORT "$be_starlet_port"
    require_uint STARROCKS_WAIT_ATTEMPTS "$wait_attempts"
    require_uint STARROCKS_WAIT_INTERVAL_SECONDS "$wait_interval_seconds"

    export JAVA_HOME="''${JAVA_HOME:-${openjdk21}}"
    export HOME="''${HOME:-$state_dir/home-env}"

    run_dir="$state_dir/run"
    fe_state="$state_dir/fe"
    be_state="$state_dir/be"
    env_file="$state_dir/starrocks-test-env.sh"
    fe_pid=""
    be_pid=""
    stop_requested=0

    mkdir -p "$run_dir" "$HOME"

    dump_logs() {
      log "===== FE stdout =====" >&2
      tail -120 "$run_dir/fe.stdout" >&2 || true
      log "===== FE logs =====" >&2
      find "$fe_state/log" -maxdepth 1 -type f -print -exec tail -120 {} \; >&2 || true
      log "===== BE stdout =====" >&2
      tail -160 "$run_dir/be.stdout" >&2 || true
      log "===== BE logs =====" >&2
      find "$be_state/log" -maxdepth 1 -type f -print -exec tail -160 {} \; >&2 || true
    }

    child_pids() {
      local parent="$1"

      ps -axo pid=,ppid= | awk -v parent="$parent" '$2 == parent { print $1 }'
    }

    descendant_pids() {
      local parent="$1"
      local child

      while IFS= read -r child; do
        if [[ -z "$child" ]]; then
          continue
        fi

        descendant_pids "$child"
        printf '%s\n' "$child"
      done < <(child_pids "$parent")
    }

    terminate_tree() {
      local root_pid="$1"
      local signal="''${2:-TERM}"
      local target
      local targets=()

      if [[ -z "$root_pid" ]]; then
        return
      fi

      mapfile -t targets < <(
        {
          descendant_pids "$root_pid"
          printf '%s\n' "$root_pid"
        } | awk 'NF && !seen[$1]++'
      )

      for target in "''${targets[@]}"; do
        kill "-$signal" "$target" 2>/dev/null || true
      done

      if [[ "$signal" == "KILL" ]]; then
        return
      fi

      sleep 2

      for target in "''${targets[@]}"; do
        if kill -0 "$target" 2>/dev/null; then
          kill -KILL "$target" 2>/dev/null || true
        fi
      done
    }

    cleanup() {
      local status=$?
      set +e

      if [[ "$status" -ne 0 && "$stop_requested" -eq 0 ]]; then
        dump_logs
      fi

      terminate_tree "$be_pid" KILL
      terminate_tree "$fe_pid"
      wait "$be_pid" 2>/dev/null || true
      wait "$fe_pid" 2>/dev/null || true

      if [[ "$stop_requested" -ne 0 ]]; then
        log "Stopped StarRocks single-node local runner"
      fi
    }

    request_stop() {
      stop_requested=1
    }

    trap cleanup EXIT
    trap request_stop INT TERM

    mysql_query() {
      mysql --connect-timeout=2 -h "$host" -P "$query_port" -uroot "$@"
    }

    wait_for_fe() {
      local _attempt

      for _attempt in $(seq 1 "$wait_attempts"); do
        if mysql_query -e 'SELECT 1;' >/dev/null 2>&1; then
          return 0
        fi

        if ! kill -0 "$fe_pid" 2>/dev/null; then
          fail "StarRocks FE exited before becoming queryable"
        fi

        sleep "$wait_interval_seconds"
      done

      fail "StarRocks FE did not become queryable at $host:$query_port"
    }

    backend_alive() {
      local backends="$1"

      printf '%s\n' "$backends" \
        | grep -F "$advertise_host" \
        | grep -F "$be_heartbeat_port" \
        | grep -F true >/dev/null
    }

    wait_for_be_alive() {
      local _attempt
      local backends

      for _attempt in $(seq 1 "$wait_attempts"); do
        backends="$(mysql_query --skip-column-names --batch -e 'SHOW BACKENDS;' 2>/dev/null || true)"
        if backend_alive "$backends"; then
          return 0
        fi

        if ! kill -0 "$be_pid" 2>/dev/null; then
          printf '%s\n' "$backends" >&2
          fail "StarRocks BE exited before becoming alive"
        fi

        sleep "$wait_interval_seconds"
      done

      log "StarRocks BE did not become alive. Last SHOW BACKENDS output:" >&2
      mysql_query --skip-column-names --batch -e 'SHOW BACKENDS;' >&2 || true
      exit 1
    }

    write_fe_conf() {
      mkdir -p "$fe_state/log" "$fe_state/meta"
      cat > "$fe_state/home/conf/fe.conf" <<EOF
    LOG_DIR = $fe_state/log
    DATE = "$(date +%Y%m%d-%H%M%S)"
    JAVA_OPTS="''${STARROCKS_FE_JAVA_OPTS:--Dlog4j2.formatMsgNoLookups=true -Xmx1024m -XX:+UseG1GC -XX:ErrorFile=$fe_state/log/hs_err_pid%p.log -Djava.security.policy=$fe_state/home/conf/udf_security.policy}"
    sys_log_level = INFO
    http_port = $fe_http_port
    rpc_port = $fe_rpc_port
    query_port = $query_port
    edit_log_port = $fe_edit_log_port
    mysql_service_nio_enabled = true
    meta_dir = $fe_state/meta
    sys_log_dir = $fe_state/log
    audit_log_dir = $fe_state/log
    priority_networks = $host/32
    EOF
    }

    write_be_conf() {
      mkdir -p "$be_state/log" "$be_state/storage"
      cat > "$be_state/home/conf/be.conf" <<EOF
    sys_log_level = INFO
    be_port = $be_port
    be_http_port = $be_http_port
    heartbeat_service_port = $be_heartbeat_port
    brpc_port = $be_brpc_port
    starlet_port = $be_starlet_port
    storage_root_path = $be_state/storage
    sys_log_dir = $be_state/log
    priority_networks = $host/32
    JAVA_OPTS="''${STARROCKS_BE_JAVA_OPTS:---add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED}"
    EOF
    }

    register_backend() {
      if ! mysql_query --skip-column-names --batch -e 'SHOW BACKENDS;' | grep -F "$advertise_host" | grep -F "$be_heartbeat_port" >/dev/null; then
        mysql_query -e "ALTER SYSTEM ADD BACKEND \"$advertise_host:$be_heartbeat_port\";" || true
      fi
    }

    start_fe() {
      ${starrocksPackage}/bin/starrocks-prepare-runtime fe "$fe_state"
      write_fe_conf

      (
        trap "" INT
        component_pid=""
        cd "$fe_state/home"
        SYS_LOG_TO_CONSOLE=1 "$fe_state/home/bin/start_fe.sh" --host_type IP --logconsole > "$run_dir/fe.stdout" 2>&1 &
        component_pid=$!
        wait "$component_pid" 2>/dev/null || true
      ) &
      fe_pid=$!
    }

    start_be() {
      ${starrocksPackage}/bin/starrocks-prepare-runtime be "$be_state"
      write_be_conf

      (
        trap "" INT
        component_pid=""
        cd "$be_state/home"
        LOG_CONSOLE=1 "$be_state/home/bin/start_be.sh" --be --logconsole > "$run_dir/be.stdout" 2>&1 &
        component_pid=$!
        wait "$component_pid" 2>/dev/null || true
      ) &
      be_pid=$!
    }

    dsn="mysql://root@$host:$query_port/$database"

    log "Starting StarRocks single-node local runner"
    log "State dir: $state_dir"
    log "FE query port: $query_port"
    log "BE heartbeat port: $be_heartbeat_port"

    start_fe
    wait_for_fe
    register_backend
    start_be
    wait_for_be_alive

    mysql_query -e "CREATE DATABASE IF NOT EXISTS \`$database\`;"

    printf 'export STARROCKS_TEST_DSN=%q\n' "$dsn" > "$env_file"

    log "StarRocks is ready"
    log "STARROCKS_TEST_DSN=$dsn"
    log "export STARROCKS_TEST_DSN=$(printf '%q' "$dsn")"
    log "Wrote $env_file"
    log "Press Ctrl-C to stop FE/BE"

    while [[ "$stop_requested" -eq 0 ]]; do
      if ! kill -0 "$fe_pid" 2>/dev/null; then
        fail "StarRocks FE exited"
      fi

      if ! kill -0 "$be_pid" 2>/dev/null; then
        fail "StarRocks BE exited"
      fi

      sleep 2
    done
  '';

  meta = {
    description = "Run a persistent local single-node StarRocks FE/BE for development and tests";
    homepage = "https://www.starrocks.io/";
    license = lib.licenses.asl20;
    mainProgram = "starrocks-single-node-local";
    platforms = starrocksPackage.meta.platforms or [ ];
  };
}
