#!/bin/sh

# --------------------- 00-var.sh ---------------------
# This file contains global variables and settings for the script.

# Service config
excluded_services="" # split by '|' and no space, example: excluded_services="mysql|nginx"
included_services="" # only config if somehow service is excluded by predifined settings

# Predefined service config
predefined_excluded_services="accounts-daemon|alsa-|anacron|apport|apt-|arp-|audit-|auth-rpcgss-|auto-cpu|avahi-daemon|blk-availability|bolt|cgroupfs-mount|chrony|cloud-|connman|console-|containerd|cpupower|cron|cryptdisks|cups|dbus|debug-shell|dm-event|dmesg|dnf-|dpkg|dracut-|e2scrub|emergency|esm-cache|finalrd|friendly-recovery|fstrim|fwupd|getty|getty-|gpu-manager|grub-|grub2-|haveged|hwclock|ifup|initrd-|ipset|irqbalance|iscsi|kbd|kdump|keyboard-setup|kmod|kvm_|landscape-|ldconfig|logrotate|lvm-devices|lvm2|lxd-agent|man-db|mdcheck|mdmonitor|microcode|mkinitcpio-|ModemManager|modprobe|motd-news|multipath-|multipathd|netplan-ovs-cleanup|networkd-dispatcher|networking|NetworkManager|nfs-common|nfs-idmapd|nfs-utils|nis-|nm-|nslcd|open-iscsi|packagekit|pam_namespace|phpsessionclean|plymouth|polkit|pollinate|power-profiles-|procps|quotaon|raid-|rc-local|rc.service|rcS.service|rdisc|rescue|rescue.service|rpc-gssd|rpc-statd|rpc-svcgssd|rpmdb-|rsync|rtkit-|screen-cleanup|sddm|secureboot-db|selinux-|serial-getty|setvtrgb|smartmontools|snap|snmpd|ssh|sssd|sudo|switcheroo-control|sysstat-|system-update-cleanup|system76-|systemd-|thermald|tlp|tuned|ua-reboot-cmds|ua-timer|ubuntu-advantage|udev|udisks2|unattended-upgrades|update-hosts|update-notifier-download|update-notifier-motd|upower|usbmuxd|user-|user@|uuidd|vgauth|wazuh-indexer-|wpa_supplicant|wsl-|wtmpdb-|x11-common|xfs_scrub_all"

motd_ver="2.1.14_202608081506"

# Repo URL
REPO="zharfanug/zn-motd"
VER_URL="https://raw.githubusercontent.com/${REPO}/latest/VERSION"
INSTALL_URL="https://raw.githubusercontent.com/${REPO}/latest/install.sh"

# Data
TMP_DIR=${HOME:-/tmp}
DATA_DIR_NAME=".zn-motd"
DATA_DIR="${TMP_DIR}/${DATA_DIR_NAME}"
VER_FILE_prefix="remote-ver_"
PUB_IP_FILE_prefix="pub-ip_"
ASN_FILE_prefix="asn-org_"
MOTD_FILE="zn-motd.sh"
STARTUP_DIR="/etc/profile.d"
BIN_FILE="motd"

# Usage threshold
warn_usage=50
max_usage=85

# Spacing
LABEL_WIDTH=12

# Colors
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
# --------------------- 20-prereq.sh ---------------------
# This file contains prerequisite checks for the script.

require_cmd_list "awk" "grep" "cut" "date"

CURRENT_DATE=$(date +'%Y%m%d')

VER_FILE="${VER_FILE_prefix}${CURRENT_DATE}"
PUB_IP_FILE="${PUB_IP_FILE_prefix}${CURRENT_DATE}"
ASN_FILE="${ASN_FILE_prefix}${CURRENT_DATE}"
# --------------------- 30-active_logins.sh ---------------------
# This file contains functions to retrieve and display active logins.

ACTIVE_LOGINS_LIST=""

# who's default output is a stable, standardized format shared by GNU
# coreutils/util-linux/BSD: "user  line  date/time  (origin)", origin
# being optional and either an IP, a hostname, or a display like ":0".
# The date/time formatting itself is NOT stable though — e.g. on this
# system it's "2026-07-27 07:48" normally but "Jul 27 07:48" (no year)
# under LC_ALL=C, so don't force a locale here, and don't match a fixed
# date pattern either: just take everything between the terminal field
# and the optional trailing "(origin)" as the datetime, whatever shape
# it comes in.
get_active_logins() {
  if [ -n "$ACTIVE_LOGINS_LIST" ]; then
    return 0
  fi

  if ! command -v who >/dev/null 2>&1; then
    return 0
  fi

  _raw=$(who 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  ACTIVE_LOGINS_LIST=$(printf '%s\n' "$_raw" | awk '
    {
      if ($1 == "") next

      origin = "-"
      if (match($0, /\([^)]*\)/)) {
        origin = substr($0, RSTART + 1, RLENGTH - 2)
      }

      body = $0
      sub(/\([^)]*\).*$/, "", body)
      gsub(/[[:space:]]+$/, "", body)

      n = split(body, tok, /[[:space:]]+/)
      extra = n - 1
      if (min_extra == 0 || extra < min_extra) min_extra = extra

      users[NR] = tok[1]
      origins[NR] = origin
      ntoks[NR] = n
      extras[NR] = extra
      for (i = 2; i <= n; i++) toks[NR, i] = tok[i]
    }
    END {
      # The date/time token count stays constant across a single `who`
      # run (same locale, same command), so bootstrap it from whichever
      # row has the fewest extra tokens -- that must be a row with a
      # plain one-token terminal (pts/0, tty1, seat0, etc). Any row with
      # more extra tokens than that baseline has a multi-token terminal
      # instead of a wider date (seen in the wild: some sshd setups
      # record a compound line like "sshd pts/4"), so the surplus folds
      # into the terminal instead of leaking into the date/time column.
      date_tokens = min_extra - 1
      if (date_tokens < 1) date_tokens = 1

      for (r = 1; r <= NR; r++) {
        if (!(r in ntoks)) continue

        term_count = extras[r] - date_tokens
        if (term_count < 1) term_count = 1

        term = ""
        for (i = 2; i <= 1 + term_count; i++) {
          term = (term == "" ? toks[r, i] : term " " toks[r, i])
        }

        dt = ""
        for (i = 2 + term_count; i <= ntoks[r]; i++) {
          dt = (dt == "" ? toks[r, i] : dt " " toks[r, i])
        }

        print users[r] "|" term "|" dt "|" origins[r]
      }
    }')

  return 0
}

print_active_logins() {
  get_active_logins

  if [ -z "$ACTIVE_LOGINS_LIST" ]; then
    return 0
  fi

  # Dynamic per-column width (like the Services grid) instead of guessed
  # fixed widths, seeded with the header labels' own lengths so a short
  # column still fits its header.
  _widths=$(printf '%s\n' "$ACTIVE_LOGINS_LIST" | awk -F'|' '
    BEGIN { w1 = 4; w2 = 8; w3 = 13; w4 = 4 }
    {
      if (length($1) > w1) w1 = length($1)
      if (length($2) > w2) w2 = length($2)
      if (length($3) > w3) w3 = length($3)
      if (length($4) > w4) w4 = length($4)
    }
    END { print w1, w2, w3, w4 }')

  IFS=' ' read -r _w1 _w2 _w3 _w4 <<EOF
$_widths
EOF

  printf "%bActive Logins:\n" "$W"
  printf "%b  %-*s | %-*s | %-*s | %s\n" "$W" "$_w1" "User" "$_w2" "Terminal" "$_w3" "Session Start" "From"

  while IFS='|' read -r _user _term _dt _origin; do
    [ -z "$_user" ] && continue
    printf "  %-*s | %-*s | %-*s | %s\n" "$_w1" "$_user" "$_w2" "$_term" "$_w3" "$_dt" "$_origin"
  done <<EOF
$ACTIVE_LOGINS_LIST
EOF
  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
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
# --------------------- 30-res_usage.sh ---------------------
# This file contains functions to retrieve and display resource usage.

CPU_USED_PERCENT=""
PROCESSOR_COUNT=""
MEM_USED_PERCENT=""
MEM_USED_H=""
MEM_TOTAL_H=""
DISK_LIST=""

# Formats a byte count as IEC binary units (Ki/Mi/Gi/...), dropping the
# decimal when it's a whole number so "15Gi" doesn't print as "15.0Gi".
_bytes_to_human() {
  awk -v b="$1" 'BEGIN {
    split("B Ki Mi Gi Ti Pi", units, " ")
    v = b; u = 1
    while (v >= 1024 && u < 6) { v /= 1024; u++ }
    if (v == int(v)) printf "%d%s", v, units[u]
    else printf "%.1f%s", v, units[u]
  }'
}

get_cpu_usage() {
  if [ -n "$CPU_USED_PERCENT" ]; then
    return 0
  fi

  # Preferred: sysstat's collected `sar -u` data, if the sadc cron job has
  # already logged samples for today — reading it back is instant, unlike
  # mpstat/proc-stat below which both have to block for a live sample.
  # No time/count args means "report today's log", not "sample live now".
  if command -v sar >/dev/null 2>&1; then
    _raw=$(LC_ALL=C sar -u 2>/dev/null)
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
      # Find the field index of "all" on each row and grab that row's last
      # field. Scanning by field (not fixed position) survives the
      # AM/PM-vs-ISO timestamp width swing controlled by S_TIME_FORMAT,
      # and re-running per line keeps the most recent sample, not the
      # restart/header lines sar intersperses after a reboot. The trailing
      # "Average:" summary row also has an "all" field, so skip it
      # explicitly or it'd win as the "last" match instead of a real sample.
      _idle=$(printf '%s\n' "$_raw" | awk '{
        if ($1 == "Average:") next
        for (i = 1; i <= NF; i++) if ($i == "all") idle = $NF
      } END { print idle }')
      if printf '%s' "$_idle" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
        CPU_USED_PERCENT=$(awk -v idle="$_idle" 'BEGIN { printf "%.0f", 100 - idle }')
      fi
    fi
  fi

  if [ -n "$CPU_USED_PERCENT" ]; then
    return 0
  fi

  # Fallback: sysstat's mpstat. One real one-second sample, LC_ALL=C so
  # the "Average:" label and decimal point stay locale-independent.
  if command -v mpstat >/dev/null 2>&1; then
    _raw=$(LC_ALL=C mpstat 1 1 2>/dev/null)
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
      # %idle is always the last column regardless of sysstat version
      # (older/newer releases add or drop %guest, %gnice, etc).
      _idle=$(printf '%s\n' "$_raw" | awk '/^Average:/ {print $NF}')
      if printf '%s' "$_idle" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
        CPU_USED_PERCENT=$(awk -v idle="$_idle" 'BEGIN { printf "%.0f", 100 - idle }')
      fi
    fi
  fi

  if [ -n "$CPU_USED_PERCENT" ]; then
    return 0
  fi

  # Fallback: two /proc/stat samples one second apart (Linux only, no
  # extra package required). Whole-second sleep for portability — old
  # busybox/POSIX sleep implementations reject fractional seconds.
  if [ -r /proc/stat ]; then
    _s1=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++){t+=$i}; print t, $5+$6}' /proc/stat)
    sleep 1
    _s2=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++){t+=$i}; print t, $5+$6}' /proc/stat)
    if [ -n "$_s1" ] && [ -n "$_s2" ]; then
      CPU_USED_PERCENT=$(awk -v s1="$_s1" -v s2="$_s2" '
        BEGIN {
          split(s1, a, " "); split(s2, b, " ")
          dt = b[1] - a[1]; didle = b[2] - a[2]
          if (dt > 0) printf "%.0f", (dt - didle) * 100 / dt
        }')
    fi
  fi

  if [ -n "$CPU_USED_PERCENT" ]; then
    return 0
  fi

  # Last resort: one-shot `top`. Handles procps ("... 79.5 id ...", Linux),
  # busybox ("... 79% idle ..."), and BSD/OPNsense ("..., 100% idle") by
  # stripping '%'/',' and scanning fields for the "id"/"idle" label instead
  # of assuming a fixed layout.
  if command -v top >/dev/null 2>&1; then
    _cpu_line=$(LC_ALL=C top -bn1 2>/dev/null | grep -iE '^%?Cpu|^CPU:' | head -n1)
    if [ -n "$_cpu_line" ]; then
      _idle=$(printf '%s\n' "$_cpu_line" | tr -d '%' | tr ',' ' ' | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "id" || $i == "idle") { print $(i - 1); exit }
        }
      }')
      if printf '%s' "$_idle" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
        CPU_USED_PERCENT=$(awk -v idle="$_idle" 'BEGIN { printf "%.0f", 100 - idle }')
      fi
    fi
  fi

  return 0
}

get_processor_count() {
  if [ -n "$PROCESSOR_COUNT" ]; then
    return 0
  fi

  if command -v nproc >/dev/null 2>&1; then
    _n=$(nproc 2>/dev/null)
    _rc=$?
    [ "$_rc" -eq 0 ] && [ -n "$_n" ] && PROCESSOR_COUNT="$_n"
  fi

  if [ -n "$PROCESSOR_COUNT" ]; then
    return 0
  fi

  if command -v getconf >/dev/null 2>&1; then
    _n=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    _rc=$?
    [ "$_rc" -eq 0 ] && [ -n "$_n" ] && PROCESSOR_COUNT="$_n"
  fi

  if [ -n "$PROCESSOR_COUNT" ]; then
    return 0
  fi

  if [ -r /proc/cpuinfo ]; then
    _n=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    if [ -n "$_n" ] && [ "$_n" -gt 0 ] 2>/dev/null; then
      PROCESSOR_COUNT="$_n"
    fi
  fi

  if [ -n "$PROCESSOR_COUNT" ]; then
    return 0
  fi

  # BSD/OPNsense/macOS
  if command -v sysctl >/dev/null 2>&1; then
    _n=$(sysctl -n hw.ncpu 2>/dev/null)
    _rc=$?
    [ "$_rc" -eq 0 ] && [ -n "$_n" ] && PROCESSOR_COUNT="$_n"
  fi

  return 0
}

get_mem_usage() {
  if [ -n "$MEM_USED_PERCENT" ]; then
    return 0
  fi

  _total_b=""
  _used_b=""

  # Preferred: /proc/meminfo (Linux). MemAvailable (kernel >=3.14) already
  # accounts for reclaimable cache/buffers, matching what `free` calls
  # "available" — much closer to "actually used" than MemFree alone.
  if [ -r /proc/meminfo ]; then
    _total_kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
    _avail_kb=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)
    if [ -z "$_avail_kb" ]; then
      # Older kernels lack MemAvailable; approximate it the way `free` used to.
      _avail_kb=$(awk '
        /^MemFree:/ { f = $2 }
        /^Buffers:/ { b = $2 }
        /^Cached:/ && $1 != "SwapCached:" { c = $2 }
        END { print f + b + c }
      ' /proc/meminfo)
    fi
    if [ -n "$_total_kb" ] && [ "$_total_kb" -gt 0 ] 2>/dev/null && [ -n "$_avail_kb" ]; then
      _total_b=$((_total_kb * 1024))
      _used_b=$(((_total_kb - _avail_kb) * 1024))
    fi
  fi

  # Fallback: FreeBSD/OPNsense via sysctl — no /proc there.
  if [ -z "$_total_b" ] && command -v sysctl >/dev/null 2>&1; then
    _pagesize=$(sysctl -n hw.pagesize 2>/dev/null)
    _free_pages=$(sysctl -n vm.stats.vm.v_free_count 2>/dev/null)
    _physmem=$(sysctl -n hw.physmem 2>/dev/null)
    if [ -n "$_pagesize" ] && [ -n "$_free_pages" ] && [ -n "$_physmem" ] \
       && [ "$_physmem" -gt 0 ] 2>/dev/null; then
      _total_b="$_physmem"
      _used_b=$((_physmem - _free_pages * _pagesize))
    fi
  fi

  # Last resort: `free`'s own "used" column (3rd field of the Mem: row in
  # both old and new procps layouts), so we don't have to reimplement its
  # available-memory heuristics ourselves.
  if [ -z "$_total_b" ] && command -v free >/dev/null 2>&1; then
    _line=$(LC_ALL=C free -b 2>/dev/null | awk '/^Mem:/ {print; exit}')
    if [ -n "$_line" ]; then
      _total_b=$(printf '%s' "$_line" | awk '{print $2}')
      _used_b=$(printf '%s' "$_line" | awk '{print $3}')
    fi
  fi

  if [ -z "$_total_b" ] || ! printf '%s' "$_total_b" | grep -qE '^[0-9]+$' \
     || [ "$_total_b" -le 0 ] 2>/dev/null; then
    return 0
  fi

  MEM_USED_PERCENT=$(awk -v u="$_used_b" -v t="$_total_b" 'BEGIN { printf "%.2f", u * 100 / t }')
  MEM_USED_H=$(_bytes_to_human "$_used_b")
  MEM_TOTAL_H=$(_bytes_to_human "$_total_b")

  return 0
}

get_disk_usage() {
  if [ -n "$DISK_LIST" ]; then
    return 0
  fi

  if ! command -v df >/dev/null 2>&1; then
    return 0
  fi

  # 1024-block counts (not -h) so the percentage can be computed to 2
  # decimals ourselves instead of relying on df's own rounded-to-integer
  # Capacity column; human-readable strings are rendered afterwards via
  # _bytes_to_human, same as Memory, for one consistent format.
  _has_type=true
  _raw=$(LC_ALL=C df -kPT 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    # -T (filesystem type column) is a GNU/busybox extension; without it
    # we can't denylist by type, so fall back to denylisting pseudo
    # mountpoint prefixes instead (mainly matters on BSD/OPNsense, which
    # don't have an efivarfs-under-/sys to worry about excluding anyway).
    _has_type=false
    _raw=$(LC_ALL=C df -kP 2>/dev/null)
    _rc=$?
  fi

  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  if [ "$_has_type" = true ]; then
    _rows=$(printf '%s\n' "$_raw" | awk '
      NR == 1 { next }
      {
        type = $2
        if (type ~ /^(tmpfs|devtmpfs|efivarfs|proc|sysfs|cgroup|cgroup2|devpts|securityfs|debugfs|tracefs|pstore|bpf|mqueue|hugetlbfs|fusectl|configfs|autofs|rpc_pipefs|overlay|squashfs|binfmt_misc|none)$/) next
        if ($3 !~ /^[0-9]+$/ || $3 + 0 == 0) next
        mnt = $7
        for (i = 8; i <= NF; i++) mnt = mnt " " $i
        if (mnt ~ /^\/boot($|\/)/) next
        # Same source device mounted at several paths (btrfs subvolumes,
        # bind mounts) reports identical usage everywhere; keep only the
        # first mountpoint seen for each source so the list isn'"'"'t just
        # the same numbers repeated.
        if (seen[$1]++) next
        print $3 "|" $4 "|" mnt
      }')
  else
    _rows=$(printf '%s\n' "$_raw" | awk '
      NR == 1 { next }
      {
        mnt = $6
        for (i = 7; i <= NF; i++) mnt = mnt " " $i
        if (mnt ~ /^\/(proc|sys|dev|boot)($|\/)/) next
        if ($2 !~ /^[0-9]+$/ || $2 + 0 == 0) next
        if (seen[$1]++) next
        print $2 "|" $3 "|" mnt
      }')
  fi

  if [ -z "$_rows" ]; then
    return 0
  fi

  # Per-row human formatting has to happen in the shell (awk can't call
  # _bytes_to_human), so walk the filtered rows via heredoc — a pipe would
  # run this in a subshell and lose _list once the loop ends.
  _list=""
  while IFS='|' read -r _total_kb _used_kb _mnt; do
    [ -z "$_total_kb" ] && continue
    _pct=$(awk -v u="$_used_kb" -v t="$_total_kb" 'BEGIN { printf "%.2f", u * 100 / t }')
    _used_h=$(_bytes_to_human $((_used_kb * 1024)))
    _total_h=$(_bytes_to_human $((_total_kb * 1024)))
    _entry="${_pct}|${_used_h}|${_total_h}|${_mnt}"
    if [ -n "$_list" ]; then
      _list="${_list}
${_entry}"
    else
      _list="$_entry"
    fi
  done <<EOF
$_rows
EOF

  [ -n "$_list" ] && DISK_LIST="$_list"

  return 0
}

print_res_usage() {
  get_cpu_usage
  get_processor_count

  printf "%bResources Usage:\n" "$W"

  if [ -n "$CPU_USED_PERCENT" ]; then
    _cpu_color="$G"
    if [ "$CPU_USED_PERCENT" -ge "$max_usage" ]; then
      _cpu_color="$R"
    elif [ "$CPU_USED_PERCENT" -ge "$warn_usage" ]; then
      _cpu_color="$Y"
    fi

    _cpu_suffix=""
    [ -n "$PROCESSOR_COUNT" ] && _cpu_suffix=" (${PROCESSOR_COUNT} CPU)"

    printf "%b  %-*s: %b%s%%%b%s\n" "$W" "$LABEL_WIDTH" "CPU" "$_cpu_color" "$CPU_USED_PERCENT" "$W" "$_cpu_suffix"
  fi

  get_mem_usage

  if [ -n "$MEM_USED_PERCENT" ]; then
    _mem_color="$G"
    _mem_percent_int=${MEM_USED_PERCENT%.*}
    if [ "$_mem_percent_int" -ge "$max_usage" ]; then
      _mem_color="$R"
    elif [ "$_mem_percent_int" -ge "$warn_usage" ]; then
      _mem_color="$Y"
    fi

    printf "%b  %-*s: %b%s%% %b(%b%s%b / %s)\n" "$W" "$LABEL_WIDTH" "Memory" "$_mem_color" "$MEM_USED_PERCENT" "$W" "$_mem_color" "$MEM_USED_H" "$W" "$MEM_TOTAL_H"
  fi

  get_disk_usage

  if [ -n "$DISK_LIST" ]; then
    _first=true
    while IFS='|' read -r _pct _used_h _total_h _mnt; do
      [ -z "$_pct" ] && continue
      _disk_color="$G"
      _disk_pct_int=${_pct%.*}
      if [ "$_disk_pct_int" -ge "$max_usage" ]; then
        _disk_color="$R"
      elif [ "$_disk_pct_int" -ge "$warn_usage" ]; then
        _disk_color="$Y"
      fi

      if [ "$_first" = true ]; then
        printf "%b  %-*s: %b%s%% %b(%b%s%b / %s) (%s)\n" "$W" "$LABEL_WIDTH" "Disk" "$_disk_color" "$_pct" "$W" "$_disk_color" "$_used_h" "$W" "$_total_h" "$_mnt"
        _first=false
      else
        _padding=$(printf "%*s" $((LABEL_WIDTH + 4)) "")
        printf "%b%s%b%s%% %b(%b%s%b / %s) (%s)\n" "$W" "$_padding" "$_disk_color" "$_pct" "$W" "$_disk_color" "$_used_h" "$W" "$_total_h" "$_mnt"
      fi
    done <<EOF
$DISK_LIST
EOF
  fi
  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
# --------------------- 30-services.sh ---------------------
# This file contains functions to retrieve and display service status.

SERVICE_LIST=""

# trigger|remove: when a service matching "trigger" is present, drop
# services matching "remove" — alternates/aliases for the same underlying
# thing (hypervisor guest agents, db package renames) that would otherwise
# just be noise sitting inactive next to the one that's actually in use.
_SVC_OMIT_RULES='
xrdp|xrdp-
iptables|ip6tables|firewalld
nftables|iptables|firewalld
qemu-guest-agent|open-vm-tools|vmtoolsd
open-vm-tools|vmtoolsd
keepalived|ipvsadm
mariadb|mysql
mysql|mysqld
glusterd|glustereventsd|glusterfs|gluster-|nfs-blkmap|portmap|rpcbind
'

# trigger|promote: when a service matching "trigger" is present, list
# services matching "promote" first instead of plain alphabetical order.
_SVC_PROMOTE_RULES='
arkime|arkimeviewer|arkimecapture
'

_svc_build_excl_regex() {
  _e="$predefined_excluded_services"
  if [ -n "$excluded_services" ]; then
    if [ -n "$_e" ]; then
      _e="${excluded_services}|${_e}"
    else
      _e="$excluded_services"
    fi
  fi
  printf '%s' "$_e"
}

# Applies predefined+configured exclusions to "name" or "name state" lines
# ($1), then re-adds anything forced back in via included_services. An
# empty pattern group "^()" matches every line's start, so grep -v with no
# real exclusions configured would wrongly drop everything — guard for it.
_svc_filter() {
  _lines="$1"
  _excl=$(_svc_build_excl_regex)
  if [ -n "$_excl" ]; then
    _kept=$(printf '%s\n' "$_lines" | grep -viE "^(${_excl})")
  else
    _kept="$_lines"
  fi

  if [ -n "$included_services" ]; then
    _forced=$(printf '%s\n' "$_lines" | grep -iE "^(${included_services})")
    printf '%s\n%s\n' "$_kept" "$_forced" | grep -v '^$' | sort -u
  else
    printf '%s\n' "$_kept" | grep -v '^$'
  fi
}

# Sequential on purpose (mirrors the old script): a later rule's trigger
# check runs against whatever an earlier rule already removed, so e.g.
# mariadb removing "mysql" means the "mysql" rule after it won't also fire.
_svc_apply_omit_rules() {
  _list="$1"
  while IFS='|' read -r _trigger _remove; do
    [ -z "$_trigger" ] && continue
    if printf '%s\n' "$_list" | grep -qiE "^(${_trigger})"; then
      _list=$(printf '%s\n' "$_list" | grep -viE "^(${_remove})")
    fi
  done <<EOF
$_SVC_OMIT_RULES
EOF
  printf '%s' "$_list"
}

_svc_apply_promote_rules() {
  _list="$1"
  _promote_pat=""
  while IFS='|' read -r _trigger _promote; do
    [ -z "$_trigger" ] && continue
    if printf '%s\n' "$_list" | grep -qiE "^(${_trigger})"; then
      if [ -n "$_promote_pat" ]; then
        _promote_pat="${_promote_pat}|${_promote}"
      else
        _promote_pat="$_promote"
      fi
    fi
  done <<EOF
$_SVC_PROMOTE_RULES
EOF

  if [ -z "$_promote_pat" ]; then
    printf '%s\n' "$_list" | sort
    return 0
  fi

  _front=$(printf '%s\n' "$_list" | grep -iE "^(${_promote_pat})" | sort)
  _back=$(printf '%s\n' "$_list" | grep -viE "^(${_promote_pat})" | sort)
  if [ -n "$_front" ] && [ -n "$_back" ]; then
    printf '%s\n%s\n' "$_front" "$_back"
  else
    printf '%s%s\n' "$_front" "$_back"
  fi
}

# Linux, systemd. One call gets every loaded service (running or not) with
# its real state directly — no need for a slow per-service is-active call.
_svc_collect_systemd() {
  _raw=$(LC_ALL=C systemctl list-units --type=service --all --no-legend --no-pager --plain 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  printf '%s\n' "$_raw" | awk '
    {
      unit = $1
      if (unit !~ /\.service$/) next
      # LOAD column: "not-found" means systemd has a stub reference (e.g.
      # from another unit'"'"'s dependency list) but the unit file doesn'"'"'t
      # actually exist — not a real installed service, so skip it.
      if ($2 != "loaded") next
      sub(/\.service$/, "", unit)
      print unit, $3
    }'
}

# Alpine/Gentoo, OpenRC. Normalizes rc-status'"'"'s "started"/"stopped"/etc
# to the same active/inactive vocabulary systemd uses, for one shared
# color rule downstream.
_svc_collect_openrc() {
  _raw=$(LC_ALL=C rc-status --all --nocolor 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  printf '%s\n' "$_raw" | awk '
    /^Runlevel:/ || /^Dynamic Runlevel:/ { next }
    /\[/ {
      line = $0
      sub(/\[/, "", line); sub(/\]/, "", line)
      n = split(line, a, " ")
      if (n < 2) next
      name = a[1]
      st = (a[n] == "started") ? "active" : "inactive"
      print name, st
    }'
}

# Debian/Ubuntu without systemd (or a container faking it): the
# "service --status-all" wrapper around /etc/init.d, "[ + ]"/"[ - ]"/"[ ? ]".
_svc_collect_sysv() {
  _raw=$(LC_ALL=C service --status-all 2>&1)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  printf '%s\n' "$_raw" | awk '
    {
      if (match($0, /\[[[:space:]]*[+?-][[:space:]]*\]/)) {
        sym = substr($0, RSTART + 1, RLENGTH - 2)
        gsub(/[[:space:]]/, "", sym)
        name = substr($0, RSTART + RLENGTH)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        if (name == "") next
        st = (sym == "+") ? "active" : "inactive"
        print name, st
      }
    }'
}

# FreeBSD/OPNsense rc.d. No single command reports every enabled service's
# state at once, so filter the enabled-name list down first (exclusions
# apply the same way as everywhere else) before paying for one "service
# NAME status" call per surviving name.
_svc_collect_bsd() {
  _raw=$(service -e 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  _names=$(printf '%s\n' "$_raw" | sed 's#.*/##' | grep -v '^$')
  _names=$(_svc_filter "$_names")
  _names=$(_svc_apply_omit_rules "$_names")

  [ -z "$_names" ] && return 0

  while IFS= read -r _n; do
    [ -z "$_n" ] && continue
    _st=$(service "$_n" status 2>/dev/null)
    if printf '%s' "$_st" | grep -qiE 'is running|^running'; then
      printf '%s active\n' "$_n"
    else
      printf '%s inactive\n' "$_n"
    fi
  done <<EOF
$_names
EOF
}

get_services() {
  if [ -n "$SERVICE_LIST" ]; then
    return 0
  fi

  _raw_ns=""
  _bsd_prefiltered=false

  if command -v systemctl >/dev/null 2>&1; then
    _raw_ns=$(_svc_collect_systemd)
  elif command -v rc-status >/dev/null 2>&1; then
    _raw_ns=$(_svc_collect_openrc)
  elif command -v service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    _raw_ns=$(_svc_collect_sysv)
  elif command -v service >/dev/null 2>&1; then
    # BSD path already filters+omits internally (before the per-service
    # status calls), so don't run those steps again below.
    _raw_ns=$(_svc_collect_bsd)
    _bsd_prefiltered=true
  fi

  if [ -z "$_raw_ns" ]; then
    return 0
  fi

  if [ "$_bsd_prefiltered" = false ]; then
    _raw_ns=$(_svc_filter "$_raw_ns")
    _raw_ns=$(_svc_apply_omit_rules "$_raw_ns")
  fi

  SERVICE_LIST=$(_svc_apply_promote_rules "$_raw_ns")

  return 0
}

print_services() {
  get_services

  if [ -z "$SERVICE_LIST" ]; then
    return 0
  fi

  _svc_cols=3

  _grid=$(printf '%s\n' "$SERVICE_LIST" | awk -v cols="$_svc_cols" '
    {
      n++
      name[n] = $1
      state[n] = $2
      col = (n - 1) % cols
      if (length($1) + 1 > maxname[col]) maxname[col] = length($1) + 1
      if (length($2) > maxstate[col]) maxstate[col] = length($2)
    }
    END {
      for (i = 1; i <= n; i++) {
        col = (i - 1) % cols
        pname[col] = sprintf("%-" (maxname[col] + 2) "s", name[i] ":")
        pstate[col] = sprintf("%-" (maxstate[col] + 2) "s", state[i])
        if (col == cols - 1 || i == n) {
          line = pname[0] "|" pstate[0]
          for (c = 1; c < cols; c++) line = line "|" pname[c] "|" pstate[c]
          print line
          for (c = 0; c < cols; c++) { pname[c] = ""; pstate[c] = "" }
        }
      }
    }')

  printf "%bServices:\n" "$W"

  while IFS='|' read -r _n1 _s1 _n2 _s2 _n3 _s3; do
    [ -z "$_n1" ] && continue

    # State fields carry the grid's trailing padding spaces, so match on
    # prefix (case) rather than exact equality.
    _c1="$R"
    case "$_s1" in active*) _c1="$G" ;; esac
    printf "  %b%s%b%s%b" "$W" "$_n1" "$_c1" "$_s1" "$W"

    if [ -n "$_n2" ]; then
      _c2="$R"
      case "$_s2" in active*) _c2="$G" ;; esac
      printf "%s%b%s%b" "$_n2" "$_c2" "$_s2" "$W"
    fi

    if [ -n "$_n3" ]; then
      _c3="$R"
      case "$_s3" in active*) _c3="$G" ;; esac
      printf "%s%b%s%b" "$_n3" "$_c3" "$_s3" "$W"
    fi

    printf "\n"
  done <<EOF
$_grid
EOF
  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
# --------------------- 30-sysinfo.sh ---------------------
# This file contains functions to retrieve and display system information.

OSNAME=""
OSVER=""
UPTIME_STR=""
KERNEL_STR=""
IP_LIST=""
PUBLIC_IP=""
ASN_ORG=""
ASN_ORG=""

get_osinfo() {
  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  # Modern standard (systemd-era, covers Ubuntu/Debian/RHEL/Arch/etc.)
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OSNAME="${NAME:-}"
    OSNAME="${PRETTY_NAME:-$OSNAME}"
    OSVER="${VERSION_ID:-}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /etc/lsb-release ]; then
    OSNAME="${OSNAME:-$(grep '^DISTRIB_DESCRIPTION' /etc/lsb-release | cut -d= -f2 | tr -d '"')}"
    OSVER="${OSVER:-$(grep '^DISTRIB_RELEASE' /etc/lsb-release | cut -d= -f2 | tr -d '"')}"
    # DISTRIB_DESCRIPTION may be absent or non-English on some distros;
    # fall back to DISTRIB_ID (always ASCII) + version
    if [ -z "$OSNAME" ] || printf '%s' "$OSNAME" | grep -qE '[^[:print:]]'; then
      OSNAME=$(grep '^DISTRIB_ID' /etc/lsb-release | cut -d= -f2 | tr -d '"')
      [ -n "$OSVER" ] && OSNAME="${OSNAME} ${OSVER}"
    fi
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /etc/debian_version ]; then
    OSNAME="${OSNAME:-Debian}"
    OSVER="${OSVER:-$(cat /etc/debian_version)}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /etc/redhat-release ]; then
    OSNAME="${OSNAME:-$(cat /etc/redhat-release)}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /etc/SuSE-release ]; then
    OSNAME="${OSNAME:-$(head -n 1 /etc/SuSE-release)}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /etc/arch-release ]; then
    OSNAME="${OSNAME:-Arch Linux}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  if [ -f /usr/local/opnsense/version/core ]; then
    _core="/usr/local/opnsense/version/core"
    _osseries=$(grep '"product_series"' "$_core" | cut -d'"' -f4)
    _osnick=$(grep '"product_nickname"' "$_core" | cut -d'"' -f4)
    OSNAME=$(grep '"product_name"' "$_core" | cut -d'"' -f4)
    OSNAME="${OSNAME} ${_osseries} (${_osnick})"
    OSVER="${OSVER:-$(grep '"product_version"' "$_core" | cut -d'"' -f4)}"
  fi

  if [ -n "$OSNAME" ] && [ -n "$OSVER" ]; then
    return 0
  fi

  # Last resort: kernel name/version (covers unknown distros and BSDs)
  OSNAME="${OSNAME:-$(uname -s)}"
  OSVER="${OSVER:-$(uname -r)}"
}

get_uptime() {
  if [ -n "$UPTIME_STR" ]; then
    return 0
  fi

  if ! command -v uptime >/dev/null 2>&1; then
    return 0
  fi

  _raw=$(uptime -p 2>/dev/null)
  _rc=$?
  if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
    # Trim everything before the first digit instead of a hardcoded "up "
    # prefix, so a non-English locale's word for "up" doesn't break this.
    _uptime=$(printf '%s' "$_raw" | sed 's/^[^0-9]*//')
    [ -n "$_uptime" ] && UPTIME_STR="$_uptime"
    return 0
  fi

  _raw=$(uptime 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ -z "$_raw" ]; then
    return 0
  fi

  _seg=$(printf '%s' "$_raw" | grep -oE 'up[[:space:]]+[^,]+')
  if [ -z "$_seg" ]; then
    return 0
  fi

  _uptime=$(printf '%s' "$_seg" | sed 's/^[^0-9]*//')

  # FreeBSD/OPNsense raw format is "H:MM" — convert to "H hours, MM minutes"
  if printf '%s' "$_uptime" | grep -qE '^[0-9]+:[0-9]{2}$'; then
    _h=$(printf '%s' "$_uptime" | cut -d: -f1)
    _m=$(printf '%s' "$_uptime" | cut -d: -f2)
    if [ "$_h" -eq 1 ]; then
      _uptime="${_h} hour, ${_m} minutes"
    else
      _uptime="${_h} hours, ${_m} minutes"
    fi
  fi

  [ -n "$_uptime" ] && UPTIME_STR="$_uptime"
  return 0
}

get_kernel() {
  if [ -n "$KERNEL_STR" ]; then
    return 0
  fi

  if ! command -v uname >/dev/null 2>&1; then
    return 0
  fi

  _raw=$(uname -sr 2>/dev/null)
  _rc=$?
  if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
    KERNEL_STR="$_raw"
  fi

  return 0
}

get_ip() {
  if [ -n "$IP_LIST" ]; then
    return 0
  fi

  # Preferred: iproute2 (also covers busybox ip). Oneline mode gives one
  # address per line, so no multi-line header/inet parsing is needed.
  # "scope global" naturally excludes loopback/link-local without a
  # hardcoded 127.0.0.1 check.
  if command -v ip >/dev/null 2>&1; then
    _raw=$(ip -o -4 addr show scope global 2>/dev/null)
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
      IP_LIST=$(printf '%s\n' "$_raw" | awk '{split($4, a, "/"); print a[1], $2}')
    fi
  fi

  if [ -n "$IP_LIST" ]; then
    return 0
  fi

  # Fallback: ifconfig (net-tools, BSD/OPNsense). Interface header lines
  # start at column 0; everything else is indented, so track the current
  # interface across lines instead of relying on a distro-specific field
  # like "description:".
  if command -v ifconfig >/dev/null 2>&1; then
    _raw=$(ifconfig -a 2>/dev/null)
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
      _iface=""
      _list=""
      while IFS= read -r _line; do
        if ! printf '%s' "$_line" | grep -q '^[[:space:]]'; then
          _iface=$(printf '%s' "$_line" | sed -n 's/^\([^: ]*\).*/\1/p')
        fi
        case "$_line" in
          *inet\ *)
            _ip=$(printf '%s' "$_line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
            if [ -n "$_ip" ] && [ "$_ip" != "127.0.0.1" ]; then
              if [ -n "$_list" ]; then
                _list="${_list}
${_ip} ${_iface}"
              else
                _list="${_ip} ${_iface}"
              fi
            fi
            ;;
        esac
      done <<EOF
$_raw
EOF
      [ -n "$_list" ] && IP_LIST="$_list"
    fi
  fi

  if [ -n "$IP_LIST" ]; then
    return 0
  fi

  # Last resort: no interface name available, just the address list.
  if command -v hostname >/dev/null 2>&1; then
    _raw=$(hostname -I 2>/dev/null)
    _rc=$?
    if [ "$_rc" -eq 0 ] && [ -n "$_raw" ]; then
      IP_LIST=$(printf '%s\n' "$_raw" | tr -s '[:space:]' '\n' | sed '/^$/d' | awk '{print $1, "-"}')
    fi
  fi

  return 0
}

get_public_ip() {
  if [ -f "$DATA_DIR/$PUB_IP_FILE" ]; then
    _cached=$(cat "$DATA_DIR/$PUB_IP_FILE" 2>/dev/null)
    [ -n "$_cached" ] && PUBLIC_IP="$_cached"
  fi

  if [ -f "$DATA_DIR/$ASN_FILE" ]; then
    _cached=$(cat "$DATA_DIR/$ASN_FILE" 2>/dev/null)
    [ -n "$_cached" ] && ASN_ORG="$_cached"
  fi

  if [ -n "$PUBLIC_IP" ] && [ -n "$ASN_ORG" ]; then
    return 0
  fi

  # ip and asn_org come from the same response, so fetch once and parse both.
  _raw=""
  if command -v curl >/dev/null 2>&1; then
    _raw=$(curl -fsS --connect-timeout 3 --max-time 3 https://ifconfig.co/json 2>/dev/null)
    [ "$?" -ne 0 ] && _raw=""
  fi

  # same as curl, but fallback to wget
  if [ -z "$_raw" ] && command -v wget >/dev/null 2>&1; then
    _raw=$(wget -qO- --timeout=3 --tries=1 https://ifconfig.co/json 2>/dev/null)
    [ "$?" -ne 0 ] && _raw=""
  fi

  if [ -n "$_raw" ]; then
    PUBLIC_IP=$(printf '%s' "$_raw" | grep -o '"ip"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    ASN_ORG=$(printf '%s' "$_raw" | grep -o '"asn_org"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  fi

  # Guard against an HTML error page or truncated JSON slipping through
  # and getting cached as a bogus "IP".
  if [ -n "$PUBLIC_IP" ] && ! printf '%s' "$PUBLIC_IP" | grep -qE '^[0-9a-fA-F:.]+$'; then
    PUBLIC_IP=""
    ASN_ORG=""
  fi

  if [ -n "$PUBLIC_IP" ]; then
    update_data "$PUB_IP_FILE_prefix" "$PUBLIC_IP"
  fi
  if [ -n "$ASN_ORG" ]; then
    update_data "$ASN_FILE_prefix" "$ASN_ORG"
  fi

  return 0
}

print_sysinfo() {
  get_osinfo
  get_uptime
  get_kernel
  get_ip
  get_public_ip

  printf "%bSystem Info:\n" "$W"
  printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "OS Name" "$OSNAME"
  printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "OS Version" "$OSVER"
  if [ -n "$KERNEL_STR" ]; then
    printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "Kernel" "$KERNEL_STR"
  fi
  if [ -n "$UPTIME_STR" ]; then
    printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "Uptime" "$UPTIME_STR"
  fi

  if [ -n "$IP_LIST" ]; then
    _first=true
    while IFS= read -r _line; do
      [ -z "$_line" ] && continue
      _ip="${_line%% *}"
      _iface="${_line#* }"
      if [ "$_first" = true ]; then
        printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "IP" "${_ip} (${_iface})"
        _first=false
      else
        _padding=$(printf "%*s" $((LABEL_WIDTH + 4)) "")
        printf "%s%s (%s)\n" "$_padding" "$_ip" "$_iface"
      fi
    done <<EOF
$IP_LIST
EOF
  fi
  _pub_ip_str="${PUBLIC_IP:-Unavailable}"
  if [ -n "$PUBLIC_IP" ] && [ -n "$ASN_ORG" ]; then
    _pub_ip_str="${PUBLIC_IP} (${ASN_ORG})"
  fi
  printf "%b  %-*s: %s\n" "$W" "$LABEL_WIDTH" "Public IP" "$_pub_ip_str"
  if [ "$1" = "1" ]; then
    printf "\n"
  fi
}
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

# Runs a fresh install.sh straight off the network — never from a file on
# disk — and lets IT handle the actual install/overwrite. update_motd used
# to do that itself with cp -f, but that overwrites the very file the
# currently-running interpreter is still reading from: truncating it
# mid-execution corrupts the running process with an unexpected EOF.
# Piping a brand-new copy through sh sidesteps that entirely, since it
# never touches the file the current process has open.
install_motd() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$INSTALL_URL" | sh >/dev/null
    return $?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$INSTALL_URL" | sh >/dev/null
    return $?
  else
    log_error "Neither curl nor wget is available — please install one of them"
    exit 1
  fi
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
# --------------------- 98-print_motd.sh ---------------------
# This file contains functions to retrieve and display motd.

print_motd() {
  print_sysinfo 1
  print_res_usage 1
  print_services 1
  print_active_logins 1
  print_reboot_check 1
  check_update 1
}

# --------------------- 99-mode.sh ---------------------
# This file parses CLI arguments and dispatches which section(s) to print.
# Prints everything (print_motd) when called with no arguments.

print_usage() {
  printf '%s\n' "Usage: $(basename "$0") [OPTION]..."
  printf '\n'
  printf '%s\n' "  --help, -h          show help"
  printf '%s\n' "  --version, -V       show version"
  printf '%s\n' "  --info, -I          show system info"
  printf '%s\n' "  --resources, -R     show resource usage"
  printf '%s\n' "  --service, -S       show service status"
  printf '%s\n' "  --logins, -L        show active logins"
  printf '%s\n' "  --reboot            show reboot check"
  printf '%s\n' "  --update, -U        update to the latest version"
  printf '\n'
  printf '%s\n' "Prints everything if no option is passed."
}

print_version() {
  printf '%s %s\n' "$(basename "$0")" "$motd_ver"
}

if [ "$#" -eq 0 ]; then
  print_motd
else
  for _arg do
    case "$_arg" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --version|-V)
        print_version
        exit 0
        ;;
      --info|-I)
        print_sysinfo
        ;;
      --resources|-R)
        print_res_usage
        ;;
      --service|-S)
        print_services
        ;;
      --logins|-L)
        print_active_logins
        ;;
      --reboot)
        print_reboot_check
        ;;
      --update|-U)
        update_motd
        ;;
      *)
        printf '%s\n' "Unknown option: $_arg. Use --help for usage." >&2
        exit 1
        ;;
    esac
  done
fi
