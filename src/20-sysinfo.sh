print_sysinfo() {
  echo -e "${W}System Info:"

  osname=""
  uptime_str=""

  # Detect OS version based on available files
  if [ -f /etc/lsb-release ]; then
    osver=$(grep "DISTRIB_RELEASE" /etc/lsb-release | cut -d "=" -f 2 | sed 's/"//g')
  elif [ -f /etc/debian_version ]; then
    osver=$(cat /etc/debian_version)
  elif [ -f /etc/redhat-release ]; then
    osver=$(cat /etc/redhat-release)
  elif [ -f /etc/SuSE-release ]; then
    osver=$(cat /etc/SuSE-release)
  elif [ -f /etc/arch-release ]; then
    osver=$(cat /etc/arch-release)
  elif [ -f /usr/local/opnsense/version/core ]; then
    osver=$(grep '"product_version"' /usr/local/opnsense/version/core | cut -d '"' -f 4)
    osseries=$(grep '"product_series"' /usr/local/opnsense/version/core | cut -d '"' -f 4)
    osnick=$(grep '"product_nickname"' /usr/local/opnsense/version/core | cut -d '"' -f 4)
    osname=$(grep '"product_name"' /usr/local/opnsense/version/core | cut -d '"' -f 4)
    osname="${osname} ${osseries} (${osnick})"
    # uptime_str="$(uptime | cut -d',' -f1)"
    uptime_str=$(uptime | grep -oE "up\s+[^,]+" | sed 's/^up[[:space:]]*//')
    if echo "$uptime_str" | grep -Eq '^[0-9]+:[0-9]{2}$'; then
      # Extract hours and minutes
      hours=$(echo "$uptime_str" | cut -d':' -f1)
      minutes=$(echo "$uptime_str" | cut -d':' -f2)

      # Format the output
      if [ "$hours" -eq 1 ]; then
        uptime_str="${hours} hour, ${minutes} minutes"
      else
        uptime_str="${hours} hours, ${minutes} minutes"
      fi
    fi
  else
    osver=$(uname -r)
  fi

  if [ -z "$osname" ]; then
    osname="$(grep 'PRETTY_NAME' /etc/*release 2>/dev/null | cut -d "=" -f 2 | sed 's/"//g')"
  fi

  if [ -z "$uptime_str" ]; then
    uptime_str=$(uptime -p | cut -d ' ' -f 2-)
  fi

  # Display system information
  printf "${W}  %-*s: %s\n" "$cs" "OS Name" "$osname"
  printf "${W}  %-*s: %s\n" "$cs" "OS Version" "$osver"
  printf "${W}  %-*s: %s\n" "$cs" "Kernel" "$(uname -sr)"
  printf "${W}  %-*s: %s\n" "$cs" "Uptime" "$uptime_str"

  # Check if `ip` command exists
  if command -v ip >/dev/null 2>&1; then
    # Use `ip` command if available
    ips=$(ip a | awk '/inet / && /global/ {split($2, arr, "/"); print arr[1] " " $NF}')
    first=true
    echo "$ips" | while read -r line; do
      ip=$(echo "$line" | awk '{print $1}')
      interface=$(echo "$line" | awk '{print $2}')
      if $first; then
        printf "${W}  %-*s: %s\n" "$cs" "IP" "$ip ($interface)"
        first=false
      else
        padding=$(printf "%*s" $((cs + 3)) "")
        printf "%s %s (%s)\n" "$padding" "$ip" "$interface"
      fi
    done
  else
    # Use ifconfig
    first=true
    while IFS= read -r line; do
      if echo "$line" | grep -Eq "description"; then
        ifname=$(echo "$line" | sed -n 's/.*description: \(.*\) (.*/\1/p')
      fi
      if echo "$line" | grep -Eq "inet "; then
        ifip=$(echo "$line" | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n 1)
        if [ "$ifip" != "127.0.0.1" ]; then
          ifvhid=""
          if echo "$line" | grep -Eq "vhid "; then
            ifvhid=$(echo "$line" | grep -oE "vhid [0-9]+" | head -n 1 | awk '{print $2}')
            ifname="${ifname} - VHID${ifvhid}"
          fi
          # ips="${ips}${ifip} ${ifname}"
          if $first; then
            printf "${W}  %-*s: %s\n" "$cs" "IP" "$ifip ($ifname)"
            first=false
          else
            padding=$(printf "%*s" $((cs + 3)) "")
            printf "%s %s (%s)\n" "$padding" "$ifip" "$ifname"
          fi
          # ^ this code doesn't work 
        fi
      fi
    done <<EOF
$(ifconfig)
EOF
  fi

  
  pub_ip_info="Unavailable"
  if [ -f "$TMP_DIR/$PUB_IP_FILE" ]; then
    echo "$TMP_DIR/$PUB_IP_FILE"
    pub_ip_info=$(cat $TMP_DIR/$PUB_IP_FILE)
  else
    if command -v curl >/dev/null 2>&1; then
      pub_ip_info=$(curl -s --connect-timeout 2 --max-time 2 https://ifconfig.co/json)
    # Otherwise, check if wget exists and use it if available
    elif command -v wget >/dev/null 2>&1; then
      pub_ip_info=$(wget -qO- --timeout=2 https://ifconfig.co/json 2>/dev/null)
    fi
    if [ -z "$pub_ip_info" ]; then
      pub_ip_info="Unavailable"
    else
      ip=$(echo "$pub_ip_info" | grep -o '"ip": "[^"]*' | cut -d'"' -f4)
      asn_org=$(echo "$pub_ip_info" | grep -o '"asn_org": "[^"]*' | cut -d'"' -f4)
      pub_ip_info="$ip ($asn_org)"
      update_tmp_pre $PUB_IP_FILE_prefix
      echo $pub_ip_info > ${TMP_DIR}/$PUB_IP_FILE
      update_tmp_post $PUB_IP_FILE_prefix
    fi
  fi
  printf "${W}  %-*s: %s\n" "$cs" "Public IP" "$pub_ip_info"
}

