print_sysinfo() {
  echo -e "${W}System Info:"

  if [ -f /etc/lsb-release ]; then
    osver=$(cat /etc/lsb-release | grep "DISTRIB_RELEASE" | cut -d "=" -f 2- | sed 's/"//g')
  elif [ -f /etc/debian_version ]; then
    osver=$(cat /etc/debian_version)
  elif [ -f /etc/redhat-release ]; then
    osver=$(cat /etc/redhat-release)
  elif [ -f /etc/SuSE-release ]; then
    osver=$(cat /etc/SuSE-release)
  elif [ -f /etc/arch-release ]; then
    osver=$(cat /etc/arch-release)
  else
    osver=$(uname -r)
  fi
  
  printf "${W}  %-*s: %s\n" "$cs" "OS Name" "$(cat /etc/*release | grep "PRETTY_NAME" | cut -d "=" -f 2- | sed 's/"//g')"
  printf "${W}  %-*s: %s\n" "$cs" "OS Version" "$osver"
  printf "${W}  %-*s: %s\n" "$cs" "Kernel" "$(uname -sr)"
  printf "${W}  %-*s: %s\n" "$cs" "Uptime" "$(uptime -p | cut -d ' ' -f 2-)"

  ips=$(ip a | awk '/inet / && /global/ {split($2, arr, /\//); print arr[1] " " $NF}')

  first=true
  while read -r line; do
    ip=$(echo $line | awk '{print $1}')
    interface=$(echo $line | awk '{print $2}')
    if $first; then
      printf "${W}  %-*s: %s\n" "$cs" "IP" "$ip ($interface)"
      first=false
    else
      padding=$(printf "%*s" $(($cs + 3)) "") # +2 for ": "
      printf "%s %s (%s)\n" "$padding" "$ip" "$interface"
    fi
  done <<< "$ips"

  ip_v4=$(curl -s --max-time 3 ifconfig.me/ip)
  if [ -z "$ip_v4" ]; then
    ip_v4="Unavailable"
  fi
  printf "${W}  %-*s: %s\n" "$cs" "Public IP" "$ip_v4"
}

