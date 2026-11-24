#!/bin/sh

SCRIPT_NAME=${0##*/}
SCRIPT_BASENAME=${SCRIPT_NAME%.*}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE_DIR=$(pwd)

LOG_FILE=${LOG_FILE:-/tmp/${SCRIPT_NAME}.log}
LOG_TO_FILE=${LOG_TO_FILE:-false}

if [ -t 2 ]; then
  ESC=$(printf '\033')

  W="${ESC}[0;39m"
  R="${ESC}[1;31m"
  G="${ESC}[1;32m"
  Y="${ESC}[1;33m"
  B="${ESC}[1;34m"
  DIM="${ESC}[2m"
  C0="${ESC}[0m"
else
  W=
  R=
  G=
  Y=
  B=
  DIM=
  C0=
fi

log_format() {
  _level=$1
  shift

  _ts=$(date '+%Y-%m-%d %H:%M:%S %z')
  _msg=$_ts" - $_level : $*"

  case $_level in
    INFO)
      _print=$_msg
      _fd=1
      ;;
    WARN)
      _print=$_ts" - ${Y}WARN${C0} : $*"
      _fd=2
      ;;
    ERROR)
      _print=$_ts" - ${R}ERROR${C0} : $*"
      _fd=2
      ;;
    *)
      _print=$_msg
      _fd=1
      ;;
  esac

  printf '%b\n' "$_print" >&$_fd

  if [ "$LOG_TO_FILE" = "true" ]; then
    printf '%s\n' "$_msg" >>"$LOG_FILE"
  fi
}

log() {
  log_format INFO "$@"
}

log_warn() {
  log_format WARN "$@"
}

log_error() {
  log_format ERROR "$@"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Required command not found: $1"
    exit 1
  fi
}

require_cmd_list() {
  for cmd do
    require_cmd "$cmd"
  done
}

# Repo URL — zn-motd.sh and its checksum are release attachments, fetched
# via GitHub's "latest release" download alias (no API call, no rate
# limit, served off the same CDN as a normal release asset download).
REPO="zharfanug/zn-motd"
MOTD_URL="https://github.com/${REPO}/releases/latest/download/zn-motd.sh"
HASH_URL="https://github.com/${REPO}/releases/latest/download/zn-motd.sh.sha256"

# Data
TMP_DIR=${HOME:-/tmp}
DATA_DIR_NAME=".zn-motd"
DATA_DIR="${TMP_DIR}/${DATA_DIR_NAME}"
VER_FILE_prefix="remote-ver_"
MOTD_FILE="zn-motd.sh"
HASH_FILE="zn-motd.sh.sha256"

require_cmd_list "id" "mkdir" "chmod" "cp" "rm" "ln" "grep" "date" "awk"

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

# verify_sha256 FILE HASH_FILE — compares FILE's checksum against the one
# recorded in HASH_FILE (format: "<hex>  <filename>", as written by
# `sha256sum`). Tries the hashing tool each target platform actually
# ships (coreutils, macOS/BSD, busybox); if none are present, warns and
# skips rather than hard-failing a minimal/embedded install over a
# missing optional tool.
verify_sha256() {
  _file="$1"
  _hash_file="$2"
  _expected=$(awk '{print $1; exit}' "$_hash_file" 2>/dev/null)

  if [ -z "$_expected" ]; then
    log_warn "Could not read expected checksum from ${_hash_file} — skipping verification"
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    _actual=$(sha256sum "$_file" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    _actual=$(shasum -a 256 "$_file" | awk '{print $1}')
  elif command -v sha256 >/dev/null 2>&1; then
    _actual=$(sha256 -q "$_file" 2>/dev/null) || _actual=$(sha256 "$_file" | awk '{print $NF}')
  else
    log_warn "No sha256 tool found (sha256sum/shasum/sha256) — skipping checksum verification"
    return 0
  fi

  if [ "$_expected" != "$_actual" ]; then
    log_error "Checksum mismatch for ${_file} (expected ${_expected}, got ${_actual})"
    return 1
  fi

  log "Checksum verified for ${_file}"
  return 0
}

log "Downloading ${MOTD_URL}"
mkdir -p "$DATA_DIR" 2>/dev/null
download "$MOTD_URL" "${DATA_DIR}/${MOTD_FILE}" || exit 1

if download "$HASH_URL" "${DATA_DIR}/${HASH_FILE}"; then
  verify_sha256 "${DATA_DIR}/${MOTD_FILE}" "${DATA_DIR}/${HASH_FILE}" || exit 1
else
  log_warn "Could not download ${HASH_URL} — skipping checksum verification"
fi

chmod +x "${DATA_DIR}/${MOTD_FILE}"

STARTUP_DIR="/etc/profile.d"
BIN_DIR=""
BIN_FILE="motd"

if [ -d /usr/local/bin ]; then
  BIN_DIR="/usr/local/bin"
elif [ -d /usr/bin ]; then
  BIN_DIR="/usr/bin"
fi

if [ -z "$BIN_DIR" ]; then
  log_error "Could not find /usr/local/bin or /usr/bin to install into"
  exit 1
fi

# The real script goes in as ".${MOTD_FILE}" (dot-prefixed), so
# /etc/profile.d's own "*.sh" glob skips it, and ${MOTD_FILE} itself
# becomes a one-line shim that *runs* that file as a child process
# instead of sourcing it. /etc/profile.d/*.sh files are sourced (". $i")
# into the login shell, not executed — display managers commonly invoke
# a session-startup script with their own argument (e.g. Xsession's
# session command) and that script sources /etc/profile without
# clearing it first, so $1 inside anything /etc/profile.d sources is
# often leftover from the caller, not a real CLI flag. The old
# single-file install sourced zn-motd.sh directly, so a stray "$1" like
# that hit zn-motd.sh's "Unknown option" branch and ran `exit 1` —
# which, being sourced, killed the *login shell itself* before it ever
# got to exec the desktop session (can't log in; removing the file from
# /etc/profile.d fixes it, since nothing sources it anymore). Running it
# as a child process instead means any exit — on purpose or by bug — only
# ends that child, never the shell that's logging the user in.
REAL_MOTD_FILE=".${MOTD_FILE}"

if [ "$(id -u)" -eq 0 ]; then
  cp -f "${DATA_DIR}/${MOTD_FILE}" "${STARTUP_DIR}/${REAL_MOTD_FILE}"
  chmod +x "${STARTUP_DIR}/${REAL_MOTD_FILE}"

  printf '#!/bin/sh\n[ -x "%s" ] && "%s"\n' \
    "${STARTUP_DIR}/${REAL_MOTD_FILE}" "${STARTUP_DIR}/${REAL_MOTD_FILE}" \
    > "${STARTUP_DIR}/${MOTD_FILE}"
  chmod +x "${STARTUP_DIR}/${MOTD_FILE}"

  rm -f "${BIN_DIR}/${BIN_FILE}"
  ln -s "${STARTUP_DIR}/${REAL_MOTD_FILE}" "${BIN_DIR}/${BIN_FILE}"
  log "Installed to ${STARTUP_DIR}/${REAL_MOTD_FILE}, run at login via ${STARTUP_DIR}/${MOTD_FILE}, symlinked as ${BIN_DIR}/${BIN_FILE}"
else
  log_warn "Not running as root — installing to ${BIN_DIR}/${BIN_FILE} only; it won't run automatically at login"
  rm -f "${BIN_DIR}/${BIN_FILE}"
  if [ "$?" -ne 0 ]; then
    log_error "Failed to remove existing ${BIN_DIR}/${BIN_FILE} — try running as root"
    exit 1
  fi

  cp -f "${DATA_DIR}/${MOTD_FILE}" "${BIN_DIR}/${BIN_FILE}"
  if [ "$?" -ne 0 ]; then
    log_error "Failed to install to ${BIN_DIR}/${BIN_FILE} — try running as root"
    exit 1
  fi
  chmod +x "${BIN_DIR}/${BIN_FILE}"
fi

if ! command -v sar >/dev/null 2>&1; then
  log_warn "sysstat is not installed — CPU usage will fall back to a slower live sample"
else
  _sysstat_enabled=""

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files sysstat-collect.timer >/dev/null 2>&1; then
    systemctl is-enabled sysstat-collect.timer >/dev/null 2>&1 && _sysstat_enabled="true"
  elif [ -f /etc/default/sysstat ]; then
    grep -qE '^ENABLED="?true"?' /etc/default/sysstat 2>/dev/null && _sysstat_enabled="true"
  fi

  if [ -z "$_sysstat_enabled" ]; then
    log_warn "sysstat data collection doesn't appear to be enabled — CPU stats will use a slower live sample"
  fi
fi

if [ "$(id -u)" -eq 0 ]; then
  rm -f /home/*/${DATA_DIR_NAME}/${VER_FILE_prefix}*
fi

printf "\n==========================================================\n\n"