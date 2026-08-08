# --------------------- 10-func.sh ---------------------
# This file contains global functions for the script.

log_error() {
  printf "%bERROR: %s%b\n" "$R" "$*" "$W" >&2
}

log_warn() {
  printf "%bWARN: %s%b\n" "$Y" "$*" "$W" >&2
}

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

update_data() {
  _file_prefix=$1
  _file_content=$2
  mkdir -p "$DATA_DIR" 2>/dev/null
  rm -f -- "$DATA_DIR"/"${_file_prefix}"*
  printf '%s\n' "$_file_content" > "${DATA_DIR}/${_file_prefix}${CURRENT_DATE}"
}
