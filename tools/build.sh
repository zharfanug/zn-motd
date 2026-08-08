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

SRC_DIR="src"
BUILD_DIR="dev-build"
BUILD_FILE="motd.sh"
RELEASE=false

print_usage() {
  printf '%s\n' "Usage: $SCRIPT_NAME [OPTION]"
  printf '\n'
  printf '%s\n' "  --help          show help"
  printf '%s\n' "  --release       bump version and build zn-motd.sh at the repo root"
  printf '\n'
  printf '%s\n' "With no option, builds ${BUILD_DIR}/${BUILD_FILE} and runs it."
}

# cat concatenates src/*.sh back-to-back with nothing in between, so a
# file missing its trailing newline merges its last line into the next
# file's first line (e.g. a function's closing "}" glued to the next
# file's "#" header comment) and silently corrupts the build.
check_src_newlines() {
  for _f in "${SRC_DIR}"/*.sh; do
    if [ -n "$(tail -c1 "$_f")" ]; then
      log_warn "${_f} does not end with a newline — fixing"
      printf '\n' >> "$_f"
    fi
  done
}

build_motd() {
  log "Reading source from ${SRC_DIR}/"

  check_src_newlines

  _excl=$(awk 'NR>1{printf "|"} {printf "%s", $0}' "${SRC_DIR}/00-predefined_excluded_services")
  _ver=$(cat "VERSION" | awk '{print $1}')

  log "Version: ${_ver}"

  mkdir -p "$BUILD_DIR"
  log "Concatenating src/*.sh → ${BUILD_DIR}/${BUILD_FILE}"
  cat "${SRC_DIR}"/*.sh > "${BUILD_DIR}/${BUILD_FILE}"

  log "Patching motd_ver"
  sed -i "s|^motd_ver=.*|motd_ver=\"${_ver}\"|" "${BUILD_DIR}/${BUILD_FILE}"

  log "Patching predefined_excluded_services"
  awk -v val="$_excl" \
    '/^predefined_excluded_services=/{printf "predefined_excluded_services=\"%s\"\n", val; next} {print}' \
    "${BUILD_DIR}/${BUILD_FILE}" > "${BUILD_DIR}/${BUILD_FILE}.tmp" \
    && mv "${BUILD_DIR}/${BUILD_FILE}.tmp" "${BUILD_DIR}/${BUILD_FILE}"

  chmod +x "${BUILD_DIR}/${BUILD_FILE}"
  log "Build complete: ${BUILD_DIR}/${BUILD_FILE}"
}

# Commits VERSION + the built release file, moves the "latest" tag to that
# commit, and pushes both — only if a remote is actually configured, so
# this stays usable in a remote-less/local-only checkout too.
release_publish() {
  _ver=$(cat "VERSION")

  git add "VERSION" "${BUILD_DIR}/${BUILD_FILE}"
  git commit -m "$_ver"
  git tag -f latest

  _remote=$(git remote | head -n 1)
  if [ -z "$_remote" ]; then
    log "No git remote configured, skipping push"
    return 0
  fi

  log "Pushing to ${_remote}"
  git push "$_remote" HEAD
  git push --force "$_remote" latest
}

for _arg do
  case "$_arg" in
    --help)
      print_usage
      exit 0
      ;;
    --release)
      RELEASE=true
      ;;
    *)
      printf '%s\n' "Unknown option: $_arg. Use --help for usage." >&2
      exit 1
      ;;
  esac
done

if [ "$RELEASE" = "true" ]; then
  log "Release build: bumping version"
  ./tools/update.sh
  BUILD_DIR="$WORKSPACE_DIR"
  BUILD_FILE="zn-motd.sh"
fi

log "Starting build ($SCRIPT_NAME)"
build_motd
log "Done"

if [ "$RELEASE" = "true" ]; then
  release_publish
  exit 0
fi

printf "\n==========================================================\n\n"

"${BUILD_DIR}/${BUILD_FILE}"