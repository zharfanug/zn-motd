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
