#!/bin/bash
#
# CHECK_GALERA - Nagios/Icinga plugin to monitor MariaDB/MySQL Galera cluster node
#
# DESCRIPTION:
#   Checks key Galera and MySQL variables from the local node:
#     - Cluster size (wsrep_cluster_size)
#     - Cluster status (Primary/Non-Primary)
#     - Local node state (wsrep_local_state_comment)
#     - Connectivity and readiness (wsrep_connected, wsrep_ready)
#     - Read-only flags (read_only, super_read_only if available)
#     - Flow control paused ratio and queue metrics (wsrep_flow_control_paused, recv/send queue avg)
#
#   Supports connecting with or without credentials. If no credentials are supplied,
#   the mysql client will use ~/.my.cnf or login-paths if configured.
#
# USAGE:
#   check_galera.sh [connection options] [threshold options]
#
# EXAMPLE MONITOR USER:
#  -- MariaDB (any supported version)
#  CREATE USER 'nagios_mon'@'localhost' IDENTIFIED BY 'strong_password';
#  GRANT USAGE ON *.* TO 'nagios_mon'@'localhost';
#
# CONNECTION OPTIONS:
#   -H, --host <host>                MySQL host
#   -P, --port <port>                MySQL port (optional; if omitted, use my.cnf/mysql default)
#   -S, --socket <path>              MySQL socket path
#   -u, --user <user>                MySQL user
#   -p, --password <pass>            MySQL password (warning: visible in process list)
#       --defaults-file <path>       MySQL defaults file (must be readable by this user)
#       --mysql-cmd <path>           mysql client binary (default: mysql)
#
# THRESHOLD OPTIONS:
#   -N, --expected-size <n>          Expected wsrep_cluster_size; mismatch triggers WARNING
#       --size-critical              Escalate expected-size mismatch to CRITICAL
#       --warn-flow <pct>            WARNING if wsrep_flow_control_paused%% exceeds this (default 20)
#       --crit-flow <pct>            CRITICAL if wsrep_flow_control_paused%% exceeds this (default 50)
#
# EXIT CODES:
#   0 - OK
#   1 - WARNING
#   2 - CRITICAL
#   3 - UNKNOWN
#
# AUTHOR:
#   Mactel Team
#
# LICENSE:
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.

OK=0; WARNING=1; CRITICAL=2; UNKNOWN=3

# Defaults
# Ensure HOME is defined so mysql can locate ~/.my.cnf in restricted environments (e.g., Icinga)
if [[ -z "${HOME:-}" ]]; then
  export HOME="/var/lib/nagios"
fi

HOST=""
PORT=""
SOCKET=""
USER=""
PASSWORD=""
DEFAULTS_FILE=""
MYSQL_BIN="mysql"

EXPECTED_SIZE=""
SIZE_MISMATCH_CRITICAL=0
WARN_FLOW=20
CRIT_FLOW=50

print_usage() {
  echo "Usage: $0 [connection options] [threshold options]"
  echo "  -H|--host <host>    -P|--port <port>    -S|--socket <path>"
  echo "  -u|--user <user>    -p|--password <pass>  --defaults-file <path>  --mysql-cmd <path>"
  echo "  -N|--expected-size <n>  --size-critical  --warn-flow <pct>  --crit-flow <pct>"
}

print_help() {
  sed -n '1,120p' "$0"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)
      HOST="$2"; shift 2 ;;
    -P|--port)
      PORT="$2"; shift 2 ;;
    -S|--socket)
      SOCKET="$2"; shift 2 ;;
    -u|--user)
      USER="$2"; shift 2 ;;
    -p|--password)
      PASSWORD="$2"; shift 2 ;;
    --defaults-file)
      DEFAULTS_FILE="$2"; shift 2 ;;
    --mysql-cmd)
      MYSQL_BIN="$2"; shift 2 ;;
    -N|--expected-size)
      EXPECTED_SIZE="$2"; shift 2 ;;
    --size-critical)
      SIZE_MISMATCH_CRITICAL=1; shift ;;
    --warn-flow)
      WARN_FLOW="$2"; shift 2 ;;
    --crit-flow)
      CRIT_FLOW="$2"; shift 2 ;;
    -h|--help)
      print_help; exit $OK ;;
    *)
      echo "UNKNOWN: Unknown option: $1"; print_usage; exit $UNKNOWN ;;
  esac
done

# Ensure mysql client exists
if ! command -v "$MYSQL_BIN" >/dev/null 2>&1; then
  echo "UNKNOWN: mysql client not found ($MYSQL_BIN)"; exit $UNKNOWN
fi

# Build mysql command (note: defaults-file must come first if provided)
MYSQL_BASE_OPTS="-N -s --connect-timeout=5"
MYSQL_ARGS=""
if [[ -n "$HOST" ]]; then MYSQL_ARGS+=" -h \"$HOST\""; fi
if [[ -n "$PORT" ]]; then MYSQL_ARGS+=" -P \"$PORT\""; fi
if [[ -n "$SOCKET" ]]; then MYSQL_ARGS+=" -S \"$SOCKET\""; fi
if [[ -n "$USER" ]]; then MYSQL_ARGS+=" -u \"$USER\""; fi
if [[ -n "$PASSWORD" ]]; then MYSQL_ARGS+=" --password=\"$PASSWORD\""; fi

run_mysql() {
  local query="$1"
  if [[ -n "$DEFAULTS_FILE" ]]; then
    eval "$MYSQL_BIN --defaults-file=\"$DEFAULTS_FILE\" $MYSQL_BASE_OPTS $MYSQL_ARGS -e \"$query\"" 2>/dev/null
  else
    eval "$MYSQL_BIN $MYSQL_BASE_OPTS $MYSQL_ARGS -e \"$query\"" 2>/dev/null
  fi
}

get_status_var() {
  local var="$1"
  run_mysql "SHOW GLOBAL STATUS LIKE '$var';" | awk -F'\t' 'NF>=2{print $2}' | tr -d '\r'
}

get_variable() {
  local var="$1"
  run_mysql "SHOW VARIABLES LIKE '$var';" | awk -F'\t' 'NF>=2{print $2}' | tr -d '\r'
}

# Fetch values
WSREP_CLUSTER_SIZE="$(get_status_var wsrep_cluster_size)"
WSREP_CLUSTER_STATUS="$(get_status_var wsrep_cluster_status)"
WSREP_LOCAL_STATE="$(get_status_var wsrep_local_state)"
WSREP_LOCAL_STATE_COMMENT="$(get_status_var wsrep_local_state_comment)"
WSREP_CONNECTED="$(get_status_var wsrep_connected)"
WSREP_READY="$(get_status_var wsrep_ready)"
WSREP_FLOW_CONTROL_PAUSED="$(get_status_var wsrep_flow_control_paused)"
WSREP_RECV_QUEUE_AVG="$(get_status_var wsrep_local_recv_queue_avg)"
WSREP_SEND_QUEUE_AVG="$(get_status_var wsrep_local_send_queue_avg)"

READ_ONLY="$(run_mysql "SELECT @@GLOBAL.read_only;")"
SUPER_READ_ONLY="$(run_mysql "SELECT @@GLOBAL.super_read_only;" )"

# Basic validation: ensure we could talk to MySQL
if [[ -z "$WSREP_CLUSTER_STATUS" && -z "$WSREP_CLUSTER_SIZE" ]]; then
  echo "UNKNOWN: Unable to query MySQL/Galera status. Check credentials or local MySQL availability."
  exit $UNKNOWN
fi

# Normalize values
to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
WSREP_CONNECTED_U=$(to_upper "$WSREP_CONNECTED")
WSREP_READY_U=$(to_upper "$WSREP_READY")
WSREP_CLUSTER_STATUS_U=$(to_upper "$WSREP_CLUSTER_STATUS")
LOCAL_STATE_COMMENT=${WSREP_LOCAL_STATE_COMMENT:-Unknown}

# Flow control percent
FLOW_PCT=0
if [[ -n "$WSREP_FLOW_CONTROL_PAUSED" ]]; then
  # wsrep_flow_control_paused is 0..1 float. Convert to percent with rounding.
  FLOW_PCT=$(awk -v v="$WSREP_FLOW_CONTROL_PAUSED" 'BEGIN{ if (v=="") v=0; printf("%.0f", v*100) }')
fi

# Status evaluation
STATUS=$OK
MESSAGES=()

add_msg() { MESSAGES+=("$1"); }
set_warn() { [[ $STATUS -lt $WARNING ]] && STATUS=$WARNING; }
set_crit() { [[ $STATUS -lt $CRITICAL ]] && STATUS=$CRITICAL; }

# Connected/Ready
if [[ "$WSREP_CONNECTED_U" != "ON" ]]; then
  add_msg "wsrep_connected=$WSREP_CONNECTED (expected ON)"; set_crit
fi
if [[ "$WSREP_READY_U" != "ON" ]]; then
  add_msg "wsrep_ready=$WSREP_READY (expected ON)"; set_crit
fi

# Cluster status Primary
if [[ "$WSREP_CLUSTER_STATUS_U" != "PRIMARY" ]]; then
  add_msg "cluster_status=$WSREP_CLUSTER_STATUS (expected Primary)"; set_crit
fi

# Local state comment
if [[ -n "$LOCAL_STATE_COMMENT" && "$LOCAL_STATE_COMMENT" != "Synced" ]]; then
  add_msg "local_state=$LOCAL_STATE_COMMENT (expected Synced)"; set_warn
fi

# Expected cluster size
if [[ -n "$EXPECTED_SIZE" && -n "$WSREP_CLUSTER_SIZE" ]]; then
  if [[ "$WSREP_CLUSTER_SIZE" != "$EXPECTED_SIZE" ]]; then
    add_msg "cluster_size=$WSREP_CLUSTER_SIZE (expected $EXPECTED_SIZE)"
    if [[ $SIZE_MISMATCH_CRITICAL -eq 1 ]]; then set_crit; else set_warn; fi
  fi
fi

# Read-only flags
if [[ -n "$READ_ONLY" ]]; then
  if [[ "$READ_ONLY" != "0" ]]; then
    add_msg "read_only=ON"; set_warn
  fi
fi
if [[ -n "$SUPER_READ_ONLY" ]]; then
  if [[ "$SUPER_READ_ONLY" != "0" ]]; then
    add_msg "super_read_only=ON"; set_warn
  fi
fi

# Flow control thresholds
if [[ -n "$FLOW_PCT" ]]; then
  if [[ "$FLOW_PCT" -ge "$CRIT_FLOW" ]]; then
    add_msg "flow_control_paused=${FLOW_PCT}%>=${CRIT_FLOW}%"; set_crit
  elif [[ "$FLOW_PCT" -ge "$WARN_FLOW" ]]; then
    add_msg "flow_control_paused=${FLOW_PCT}%>=${WARN_FLOW}%"; set_warn
  fi
fi

# Construct message
BASE_MSG="cluster_size=${WSREP_CLUSTER_SIZE:-NA}, status=${WSREP_CLUSTER_STATUS:-NA}, local=${LOCAL_STATE_COMMENT}, connected=${WSREP_CONNECTED:-NA}, ready=${WSREP_READY:-NA}, read_only=${READ_ONLY:-NA}, super_read_only=${SUPER_READ_ONLY:-NA}"
if [[ ${#MESSAGES[@]} -gt 0 ]]; then
  DETAIL_MSG="; issues: ${MESSAGES[*]}"
else
  DETAIL_MSG=""
fi

# Performance data
PERF="cluster_size=${WSREP_CLUSTER_SIZE:-0}"
if [[ -n "$EXPECTED_SIZE" ]]; then PERF+=";${EXPECTED_SIZE}"; else PERF+=";;"; fi
PERF+=" flow_paused_pct=${FLOW_PCT}%;;${CRIT_FLOW};;"
PERF+=" recvq_avg=${WSREP_RECV_QUEUE_AVG:-0};;;;"
PERF+=" sendq_avg=${WSREP_SEND_QUEUE_AVG:-0};;;;"
PERF+=" read_only=${READ_ONLY:-0};;;; super_read_only=${SUPER_READ_ONLY:-0};;;;"

case $STATUS in
  $OK)       echo "OK: $BASE_MSG$DETAIL_MSG | $PERF" ;;
  $WARNING)  echo "WARNING: $BASE_MSG$DETAIL_MSG | $PERF" ;;
  $CRITICAL) echo "CRITICAL: $BASE_MSG$DETAIL_MSG | $PERF" ;;
  *)         echo "UNKNOWN: $BASE_MSG$DETAIL_MSG | $PERF" ; STATUS=$UNKNOWN ;;
esac

exit $STATUS


