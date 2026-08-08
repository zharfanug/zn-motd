#!/bin/sh

SCRIPT_NAME=$(basename "$0")
SCRIPT_BASENAME="${SCRIPT_NAME%.*}"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
WORKSPACE_DIR=$(dirname "$SCRIPT_DIR")

cd "$WORKSPACE_DIR"

. ./tools/zn-lib.sh

# OVERRIDE GLOBAL VARIABLES
LOG_TO_FILE=false

VER_FILE="VERSION"

# Bumps the patch part of "MAJOR.MINOR.PATCH_TIMESTAMP" and refreshes the
# timestamp, e.g. "2.0.0_202606151320" -> "2.0.1_202607271950".
update_ver() {
  _current=$(cut -d'_' -f1 "$VER_FILE")

  IFS='.' read -r _major _minor _patch <<EOF
$_current
EOF

  _patch=$((_patch + 1))
  _new="${_major}.${_minor}.${_patch}_$(date +'%Y%m%d%H%M')"

  printf '%s' "$_new" > "$VER_FILE"
  log "Version bumped: ${_current} -> ${_new}"
}

log "Starting update ($SCRIPT_NAME)"
update_ver
log "Done"
