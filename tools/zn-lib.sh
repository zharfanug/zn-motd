#!/bin/sh

SCRIPT_NAME=${SCRIPT_NAME:-$(basename "$0")}
SCRIPT_BASENAME="${SCRIPT_BASENAME:-${SCRIPT_NAME%.*}}"
SCRIPT_PATH=${SCRIPT_PATH:-$(realpath "$0")}
SCRIPT_DIR=${SCRIPT_DIR:-$(dirname "$SCRIPT_PATH")}
WORKSPACE_DIR=${WORKSPACE_DIR:-$(pwd)}

LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME}.log}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"

# Colors
W="\033[0;39m"     # White
R="\033[1;31m"     # Red
G="\033[1;32m"     # Green
B='\033[1;34m'     # Blue
Y="\033[1;33m"     # Yellow
DIM="\033[2m"      # Dim text
C0="\033[0m"       # Reset text style

log_format() {
  _level="$1"
  shift
  _ts="$(date '+%Y-%m-%d %H:%M:%S %z')"
  _msg="${_ts} - ${_level} : ${*}."

  _print_msg="$_msg"
  case "$_level" in
    "WARN ")
      _print_msg="${_ts} - ${Y}${_level}${C0} : ${*}."
      ;;
    "ERROR")
      _print_msg="${_ts} - ${R}${_level}${C0} : ${*}."
      ;;
  esac

  if [ "$_level" != "INFO " ]; then
    printf '%b\n' "$_print_msg" >&2
  else
    printf '%b\n' "$_print_msg"
  fi

  if [ "$LOG_TO_FILE" = "true" ]; then
    printf '%s\n' "$_msg" >> "$LOG_FILE"
  fi
}

log()       { log_format "INFO " "$@"; }
log_warn()  { log_format "WARN " "$@"; }
log_error() { log_format "ERROR" "$@"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Required command not found: $1 — please install $1"
    exit 1
  fi
}

require_cmd_list() {
  for cmd do
    require_cmd "$cmd"
  done
}

# download URL OUTPUT — curl first, wget fallback, log_error on any failure.
download() {
  _url="$1"
  _output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 --max-time 30 -o "$_output" "$_url"
    _rc=$?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_output" --timeout=5 --tries=1 "$_url"
    _rc=$?
  else
    log_error "Neither curl nor wget is available — please install one of them"
    return 1
  fi

  if [ "$_rc" -ne 0 ]; then
    log_error "Failed to download ${_url}"
  fi

  return "$_rc"
}