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
