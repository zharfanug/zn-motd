# --------------------- 97-update.sh ---------------------
# This file contains functions to check for and cache the latest remote
# motd version.

REMOTE_VER=""

get_remote_ver() {
  if [ -n "$REMOTE_VER" ]; then
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    REMOTE_VER=$(curl -fsS --connect-timeout 3 --max-time 3 "$VER_URL" 2>/dev/null)
    [ "$?" -ne 0 ] && REMOTE_VER=""
  fi

  if [ -z "$REMOTE_VER" ] && command -v wget >/dev/null 2>&1; then
    REMOTE_VER=$(wget -qO- --timeout=3 --tries=1 "$VER_URL" 2>/dev/null)
    [ "$?" -ne 0 ] && REMOTE_VER=""
  fi

  return 0
}

# check_update [1] — refreshes REMOTE_VER (network at most once a day,
# cached in $DATA_DIR/$VER_FILE). Passing "1" marks this as the passive
# call from print_motd: if a newer version is found, it also nudges the
# user via log_warn instead of just updating the cache silently.
check_update() {
  if [ -f "$DATA_DIR/$VER_FILE" ]; then
    REMOTE_VER=$(cat "$DATA_DIR/$VER_FILE" 2>/dev/null)
  else
    get_remote_ver
    [ -n "$REMOTE_VER" ] && update_data "$VER_FILE_prefix" "$REMOTE_VER"
  fi

  if [ "$1" = "1" ] && [ -n "$REMOTE_VER" ] && [ "$REMOTE_VER" != "$motd_ver" ]; then
    log_warn "A newer version is available. Run '${BIN_FILE} --update' to update."
  fi
}

# Fetches a fresh install.sh into $DATA_DIR (never touching $STARTUP_DIR)
# and runs it as a real file, not a curl|sh pipe — a piped script runs
# with no real $0, which breaks install.sh's own SCRIPT_NAME-derived
# paths, and a dropped connection mid-pipe would leave sh executing a
# half-received script. update_motd used to overwrite $STARTUP_DIR
# in place with cp -f, but that overwrites the very file the
# currently-running interpreter is still reading from: truncating it
# mid-execution corrupts the running process with an unexpected EOF.
# Downloading to $DATA_DIR first sidesteps that entirely, since it never
# touches the file the current process has open.
install_motd() {
  _installer="${DATA_DIR}/${INSTALL_FILE}"

  mkdir -p "$DATA_DIR" 2>/dev/null

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$_installer" "$INSTALL_URL"
    _rc=$?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_installer" "$INSTALL_URL"
    _rc=$?
  else
    log_error "Neither curl nor wget is available — please install one of them"
    exit 1
  fi

  if [ "$_rc" -ne 0 ]; then
    log_error "Failed to download ${INSTALL_URL}"
    return 1
  fi
  
  exec 2>/dev/null
  chmod +x "$_installer"
  "$_installer" >/dev/null
  return $?
}

update_motd() {
  rm -f "$DATA_DIR/$VER_FILE"

  check_update

  if [ -z "$REMOTE_VER" ]; then
    printf "%bUnable to check for updates.%b\n" "$R" "$W"
    return 1
  fi

  if [ "$REMOTE_VER" = "$motd_ver" ]; then
    printf "%bAlready up to date (%s).\n" "$W" "$motd_ver"
    return 0
  fi

  # Installed system-wide (root install) — only root can safely update the
  # copy in $STARTUP_DIR, since that's what every user's shell reads.
  if [ -f "${STARTUP_DIR}/${MOTD_FILE}" ] && [ "$(id -u)" -ne 0 ]; then
    log_error "This is installed system-wide — try running as root"
    exit 1
  fi

  printf "%bUpdating from %s to %s...\n" "$W" "$motd_ver" "$REMOTE_VER"

  install_motd
}
