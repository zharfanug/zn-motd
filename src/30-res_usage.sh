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
