# --------------------- 30-reboot_check.sh ---------------------
# This file contains functions to retrieve and display reboot-required status.

REBOOT_REQUIRED=""
REBOOT_REASON=""

# Debian/Ubuntu (and derivatives): apt writes this flag as soon as a
# package that needs it (kernel, libc6, etc.) is upgraded. Most reliable
# signal available, so it's tried first.
_reboot_check_debian() {
  if [ ! -s /var/run/reboot-required ]; then
    return 0
  fi

  _reason=$(head -n 1 /var/run/reboot-required 2>/dev/null)

  if [ -s /var/run/reboot-required.pkgs ]; then
    _pkgs=$(tr '\n' ',' < /var/run/reboot-required.pkgs | sed 's/,$//; s/,/, /g')
    [ -n "$_pkgs" ] && _reason="${_reason} (${_pkgs})"
  fi

  [ -z "$_reason" ] && _reason="System restart required"
  REBOOT_REQUIRED="true"
  REBOOT_REASON="$_reason"
  return 0
}

# RHEL/Fedora/CentOS via yum-utils/dnf-utils: needs-restarting -r prints
# nothing and exits 0 when no reboot is needed, exits 1 when one is.
_reboot_check_rpm() {
  if ! command -v needs-restarting >/dev/null 2>&1; then
    return 0
  fi

  needs-restarting -r >/dev/null 2>&1
  _rc=$?
  if [ "$_rc" -eq 1 ]; then
    REBOOT_REQUIRED="true"
    REBOOT_REASON="Reboot required (needs-restarting)"
  fi
  return 0
}

# FreeBSD/OPNsense: standard idiom is comparing the running kernel's ABI
# against the installed userland's — a mismatch means a newer kernel is
# on disk but not yet booted.
_reboot_check_freebsd() {
  if ! command -v freebsd-version >/dev/null 2>&1; then
    return 0
  fi

  _kernel=$(freebsd-version -k 2>/dev/null)
  _userland=$(freebsd-version -u 2>/dev/null)
  if [ -z "$_kernel" ] || [ -z "$_userland" ]; then
    return 0
  fi

  if [ "$_kernel" != "$_userland" ]; then
    REBOOT_REQUIRED="true"
    REBOOT_REASON="Running kernel (${_kernel}) differs from installed userland (${_userland})"
  fi
  return 0
}

# Generic Linux fallback for distros with no package-manager-specific
# signal above (Arch, Alpine, openSUSE, etc). These typically replace a
# single kernel package in place, so once upgraded the module directory
# for the still-running kernel version disappears immediately — its
# absence reliably means a newer kernel is already installed and waiting
# on a reboot to take effect.
_reboot_check_modules() {
  if [ ! -d /lib/modules ] && [ ! -d /usr/lib/modules ]; then
    return 0
  fi

  if ! command -v uname >/dev/null 2>&1; then
    return 0
  fi

  _running=$(uname -r 2>/dev/null)
  [ -z "$_running" ] && return 0

  _moddir="/lib/modules/${_running}"
  if [ ! -d "$_moddir" ]; then
    _moddir="/usr/lib/modules/${_running}"
  fi

  if [ -d "$_moddir" ]; then
    return 0
  fi

  REBOOT_REQUIRED="true"
  REBOOT_REASON="Modules for running kernel ${_running} are no longer installed; newer kernel available"
  return 0
}

get_reboot_check() {
  if [ -n "$REBOOT_REQUIRED" ]; then
    return 0
  fi

  _reboot_check_debian
  [ -n "$REBOOT_REQUIRED" ] && return 0

  _reboot_check_rpm
  [ -n "$REBOOT_REQUIRED" ] && return 0

  _reboot_check_freebsd
  [ -n "$REBOOT_REQUIRED" ] && return 0

  _reboot_check_modules
  return 0
}

print_reboot_check() {
  get_reboot_check

  if [ "$REBOOT_REQUIRED" != "true" ]; then
    return 0
  fi

  printf "%bReboot Required: %b%s%b\n" "$W" "$R" "$REBOOT_REASON" "$W"

  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
