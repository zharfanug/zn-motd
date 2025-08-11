#!/bin/sh

# Service config
excluded_services="" # split by '|' and no space, example: excluded_services="mysql|nginx"
included_services="" # only config if somehow service is excluded by predifined settings

# Predefined service config
predefined_excluded_services="apparmor|apport|apt-|arp-|auditd|auth-rpcgss-|blk-availability|bolt|cgroupfs-mount|chrony|cloud-|console-|containerd|cpupower|cron|cryptdisks|dbus|debug-shell|dmesg|dm-event|dnf-|dpkg|dracut-|e2scrub|emergency|esm-cache|finalrd|friendly-recovery|fstrim|fwupd|getty-|gpu-manager|grub-|grub2-|hwclock|ifup|initrd-|irqbalance|iscsi|kdump|keyboard-setup|kmod|kvm_|landscape-|ldconfig|logrotate|lvm-devices|lvm2|lxd-agent|man-db|mdcheck|mdmonitor|microcode|ModemManager|motd-news|multipath-|multipathd|netplan-ovs-cleanup|networkd-dispatcher|networking|NetworkManager|nfs-common|nfs-idmapd|nfs-utils|nis-|nm-|open-iscsi|packagekit|pam_namespace|phpsessionclean|plymouth|polkit|pollinate|procps|quotaon|raid-|rc.service|rc-local|rcS.service|rdisc|rescue.service|rpc-gssd|rpc-statd|rpc-svcgssd|rpmdb-|rsync|screen-cleanup|secureboot-db|selinux-|setvtrgb|snap|snmpd|ssh|sssd|sudo|sysstat-|systemd-|system-update-cleanup|thermald|ua-reboot-cmds|ua-timer|ubuntu-advantage|udev|udisks2|unattended-upgrades|update-notifier-download|update-notifier-motd|upower|usbmuxd|uuidd|vgauth|wazuh-indexer-|wsl-|x11-common|xfs_scrub_all"
predefined_excluded_instance_services="getty|ifup|lvm2|systemd-|user@|user-"

motd_ver="1.0.0_202508111601"

# Usage threshold
warn_usage=50
max_usage=85

# Spacing
cs=12

# Colors
W="\033[0;39m"     # White
R="\033[1;31m"     # Red
G="\033[1;32m"     # Green
Y="\033[1;33m"     # Yellow
dim="\033[2m"      # Dim text
undim="\033[0m"    # Reset text style

TMP_DIR="/tmp/zn-motd"
CURRENT_DATE=$(date +'%Y%m%d')
VER_FILE_prefix="zn-motd-ver_"
VER_FILE="${VER_FILE_prefix}${CURRENT_DATE}"
PUB_IP_FILE_prefix="zn-motd-pub-ip_"
PUB_IP_FILE="${PUB_IP_FILE_prefix}${CURRENT_DATE}"

# Clean echo from any parameter
if [ -x "/bin/echo" ]; then
  alias echo="/bin/echo"
fi

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -s "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    echo "Command 'curl' or 'wget' not found."
    exit 1
  fi
}

mkdir -p "$TMP_DIR"

update_tmp_pre() {
  FILE_PREFIX=$1
  rm $TMP_DIR/${FILE_PREFIX}* >/dev/null 2>&1
}

update_tmp_post() {
  TMP_FILE_PREFIX=$1
  TMP_FILE=$2
  sleep 1
  chown nobody:nogroup $TMP_DIR/${FILE_PREFIX}* >/dev/null 2>&1
}

show_active_logins() {
  echo -e "\n${W}Active Logins:"

  printf "  %-19s | %-10s | %-17s | %s\n" "User" "Terminal" "Session Start" "From"
  while IFS= read -r line; do
    who_str=""
    who_invalid=0
    if [ -z "$line" ]; then
      continue
    fi
    username=$(echo "$line" | awk '{print $1}')
    if ! echo "$username" | grep -Eq "^[a-zA-Z][a-zA-Z0-9_-]{2,31}$"; then
      who_invalid=$((who_invalid + 1))
    fi
    terminal=$(echo "$line" | awk '{print $2}')
    if ! echo "$terminal" | grep -Eq "^(tty[v]?[0-9]+|pts/[0-9]+|:[0-9]+|console)$"; then
      who_invalid=$((who_invalid + 1))
    fi

    temp_from=$(echo "$line" | awk '{print $5}' | tr -d '()')
    login_time=$(echo "$line" | awk '{print $3, $4}')
    if ! echo "$login_time" | grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"; then
      login_time=$(date -jf "%b %d %H:%M %Y" "$(echo "$line" | awk '{print $3, $4, $5}') $(date +"%Y")" "+%Y-%m-%d %H:%M")
      if ! echo "$login_time" | grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"; then
        who_invalid=$((who_invalid + 1))
      else
        temp_from=$(echo "$line" | awk '{print $6}' | tr -d '()')
      fi
    fi
    
    login_from=$(echo "$line" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}")
    if [ -z "$login_from" ]; then
      if echo "$terminal" | grep -Eq "^(tty[v]?[0-9]+|pts/[0-9]+|:[0-9]+|console)$"; then
        login_from="console"
      else
        who_invalid=$((who_invalid + 1))
      fi
    fi

    who_str="$(printf "  %-19s | %-10s | %-17s | %s\n" "$username" "$terminal" "$login_time" "$login_from")"
    if [ "$who_invalid" -eq 0 ]; then
      echo "$who_str"
    fi
  done <<EOF
$who_output
EOF
}

print_active_logins() {
  who_output=$(who)
  if ! [ -z "$who_output" ]; then
    show_active_logins
  fi
}

print_reboot_check() {
  # Check if reboot is required
  if [ -f /var/run/reboot-required ]; then
    echo -e "\n${W}Reboot Required: ${R}$(cat /var/run/reboot-required) ${W}"
  fi
}

print_usage() {
  usage_used=$2
  usage_used_h=$3
  usage_total=$4
  usage_total_h=$5

  usage_used_ratio=$(( usage_used * 10000 / usage_total ))
  
  if [ "$usage_used_ratio" -lt 10 ]; then
    usage_used_ratio="0$usage_used_ratio"
  fi

  usage_used_ratio_last_two=$(echo "$usage_used_ratio" | awk '{print substr($0, length($0) - 1)}')
  usage_used_ratio_rest=$(echo "$usage_used_ratio" | awk '{print substr($0, 1, length($0) - 2)}')
  usage_used_percent="${usage_used_ratio_rest}.${usage_used_ratio_last_two}"
    
  if [ "$usage_used_ratio" -lt 100 ]; then
    usage_used_percent="0$usage_used_percent"
  fi
  
  if [ "$usage_used_ratio" -le "$((warn_usage * 100))" ]; then
    usage_color=$G
  elif [ "$usage_used_ratio" -le "$((max_usage * 100))" ]; then
    usage_color=$Y
  else
    usage_color=$R
  fi
  
  if [ "$1" = "Memory" ]; then
    printf "${W}  %-*s: ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h})\n" "$cs" "${1}"
  elif [ "$1" = "DiskRoot" ]; then
    printf "${W}  %-*s: ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h}) (/)\n" "$cs" "Disk"
  elif [ "$1" = "DiskOther" ]; then
    padding=$(printf "%*s" $((cs + 3)))
    printf "${W}%s ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h}) (${6})\n" "$padding"
  fi
}

get_cpu_idle() {
  sar_tmp_file=$(mktemp)
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet sysstat; then
      if command -v sar >/dev/null 2>&1; then
        if sar -u | tail -n 2 > "$sar_tmp_file" 2>&1; then
          if cat "$sar_tmp_file" | grep "Average" >/dev/null 2>&1; then
            if sar_disk_io=$(( $(cat $sar_tmp_file | head -n 1 | awk '{print $(NF-2)}' | sed 's/\.//g' | sed 's/^0*//') + 1 - 1 ))  >/dev/null 2>&1; then
              if sar_cpu_idle=$(( $(cat $sar_tmp_file | head -n 1 | awk '{print $NF}' | sed 's/\.//g' | sed 's/^0*//') + 1 - 1 ))  >/dev/null 2>&1; then
                sar_data=true
              fi
            fi
          fi
        fi
      fi
    fi
  fi
  rm "$sar_tmp_file" >/dev/null 2>&1
}

get_cpu_idle_live() {
  # Temporary file to capture output
  tmp_file=$(mktemp)
  syntax_id=0

  # Test iostat syntax and choose the compatible one
  if iostat -c 2 -w 1 > "$tmp_file" 2>&1; then
    syntax_id=1
    syntax="iostat -c 2 -w 1"  # First format works
  elif mpstat 1 1 > "$tmp_file" 2>&1; then
    syntax_id=2
    syntax="mpstat 1 1"  # Second format works
  else
    echo "Error: Neither sysstat syntax is supported on this system."
    rm "$tmp_file" >/dev/null 2>&1
    exit 1
  fi

  # Clean up temporary file
  cpu_used_percent="0.00"
  if [ "$syntax_id" -eq 1 ]; then
    cpu_line=$(cat $tmp_file | tail -n 1)
    cpu_idle=$(echo "$cpu_line" | awk '{print $NF}')
    cpu_idle=$(expr "$cpu_idle" \* 100)
  elif [ "$syntax_id" -eq 2 ]; then
    cpu_idle=$(cat $tmp_file | awk '/Average:/ {print $NF}')
    cpu_idle=$(echo "$cpu_idle" | sed 's/\.//g' | sed 's/^0*//')
    disk_io=$(cat $tmp_file | awk '/Average:/ {print $6}')
    disk_io=$(echo "$disk_io" | sed 's/\.//g' | sed 's/^0*//')
    cpu_idle=$((cpu_idle + disk_io))
  fi
  rm "$tmp_file" >/dev/null 2>&1
}

print_cpu_usage() {
  get_cpu_idle
  if [ -n "$sar_data" ]; then
    cpu_idle=$(( sar_cpu_idle + sar_disk_io ))
  else
    get_cpu_idle_live
  fi

  cpu_used_ratio=$((10000 - cpu_idle))
  cpu_used_ratio_last_two=$(echo "$cpu_used_ratio" | awk '{print substr($0, length($0) - 1)}')
  cpu_used_ratio_rest=$(echo "$cpu_used_ratio" | awk '{print substr($0, 1, length($0) - 2)}')
  cpu_used_percent="${cpu_used_ratio_rest}.${cpu_used_ratio_last_two}"

  if [ "$cpu_idle" -eq 10000 ]; then
    cpu_used_percent="0.05"
  elif [ "$cpu_used_ratio" -lt 100 ]; then
    cpu_used_percent="0$cpu_used_percent"
  fi

  if [ "$cpu_used_ratio" -le "$((warn_usage * 100))" ]; then
    cpu_color=$G
  elif [ "$cpu_used_ratio" -le "$((max_usage * 100))" ]; then
    cpu_color=$Y
  else
    cpu_color=$R
  fi

  # Check if /proc/cpuinfo exists
  if [ -f /proc/cpuinfo ]; then
    # Linux-based: Use /proc/cpuinfo
    PROCESSOR_COUNT=$(grep -c '^processor' /proc/cpuinfo)
  else
    # FreeBSD or macOS-based: Use sysctl
    PROCESSOR_COUNT=$(sysctl -n hw.ncpu)
  fi

  printf "${W}  %-*s: ${cpu_color}%s${W} %s\n" "$cs" "CPU" "${cpu_used_percent}%" "(${PROCESSOR_COUNT} CPU)"
}

print_mem_usage() {
  # Check if 'free' command exists
  if command -v free >/dev/null 2>&1; then
    # Use free to get memory usage
    memory_info=$(free -b | grep Mem)
    memory_info_h=$(free -h | grep Mem)
    memory_used=$(echo "$memory_info" | awk '{print $3}')
    memory_used_h=$(echo "$memory_info_h" | awk '{print $3}')
    memory_total=$(echo "$memory_info" | awk '{print $2}')
    memory_total_h=$(echo "$memory_info_h" | awk '{print $2}')
  else
    # Check if 'sysctl' exists (FreeBSD/macOS alternative)
    if command -v sysctl >/dev/null 2>&1; then
      memory_used=$(ps -axo rss | awk '{rss+=$1} END {print rss}')
      memory_used_h=$(echo "scale=2; $memory_used / 1024 / 1024" | bc)
      memory_used_h=$(echo $memory_used_h | awk '{if ($1 == int($1)) print int($1); else print $1}')
      memory_used_h="${memory_used_h}G"
      memory_used=$((memory_used * 1024))
      memory_total=$(sysctl -n hw.realmem)
      memory_total_h=$(echo "scale=1; $memory_total / 1024 / 1024 / 1024" | bc)
      memory_total_h=$(echo $memory_total_h | awk '{if ($1 == int($1)) print int($1); else print $1}')
      memory_total_h="${memory_total_h}G"
    else
      echo "Unable to determine memory usage"
      exit 1
    fi
  fi
  print_usage "Memory" "$memory_used" "$memory_used_h" "$memory_total" "$memory_total_h"
}

print_disk_usage() {
  disk_root_info=$(df / | awk 'NR==2 {print $3, $2, $5}')
  disk_root_info_h=$(df -h / | awk 'NR==2 {print $3, $2, $5}')
  disk_root_used=$(echo "$disk_root_info" | awk '{print $1}')
  disk_root_used_h=$(echo "$disk_root_info_h" | awk '{print $1}')
  disk_root_total=$(echo "$disk_root_info" | awk '{print $2}')
  disk_root_total_h=$(echo "$disk_root_info_h" | awk '{print $2}')
  print_usage "DiskRoot" $disk_root_used $disk_root_used_h $disk_root_total $disk_root_total_h

  disks=$(df | grep -vP 'tmpfs|\/dev\/(?!mapper)|\/wsl|WSL2|docker\/overlay2\/' | awk '{print $6}' | tail -n +2 | grep -vE '^(/boot|/snap|/dev|/run|/init)' | grep -vE '^(/)$')
  if [ -n "$disks" ]; then
    echo "$disks" | while read -r line; do
      disk_info=$(df "$line" | awk 'NR==2 {print $3, $2, $5}')
      disk_info_h=$(df -h "$line" | awk 'NR==2 {print $3, $2, $5}')
      disk_used=$(echo "$disk_info" | awk '{print $1}')
      disk_used_h=$(echo "$disk_info_h" | awk '{print $1}')
      disk_total=$(echo "$disk_info" | awk '{print $2}')
      disk_total_h=$(echo "$disk_info_h" | awk '{print $2}')
      if [ "$disk_used" != "$disk_root_used" ] && [ "$disk_total" != "$disk_root_total" ]; then
        print_usage "DiskOther" $disk_used $disk_used_h $disk_total $disk_total_h "$line"
      fi
    done
  fi
}

print_res_usage() {
  printf "\n${W}Resources Usage:\n"
  print_cpu_usage
  print_mem_usage
  print_disk_usage
}

get_services_systemctl() {
  if ! [ -z "$excluded_services" ]; then
    predefined_excluded_services="$excluded_services|$predefined_excluded_services"
    predefined_excluded_instance_services="$excluded_services|$predefined_excluded_instance_services"
  fi
  services=$(systemctl list-unit-files --type=service --no-pager --no-legend | grep -vE "(@)" | grep -vE "^($predefined_excluded_services)" | awk '/\.service/ {print substr($1, 1, length($1)-8)}')

  instance_services=$(systemctl list-units --type=service --state=active --no-pager --no-legend | grep "@" | awk '{print $1}' | grep -vE "^($predefined_excluded_instance_services)" | awk '/\.service/ {print substr($1, 1, length($1)-8)}')
  
  services="$services $instance_services $included_services"
}

filter_and_add_service() {
  if echo "$services" | grep -q "\b$1"; then
    other_services=$(echo "$services" | tr ' ' '\n' | grep -vE "^($1)" | tr '\n' ' ')
    services="$(echo "$services" | tr ' ' '\n' | grep -E "^($2)$" | tr '\n' ' ') $other_services"
  fi
}
omit_service() {
  if echo "$services" | grep -q "\b$1"; then
    services=$(echo "$services" | tr ' ' '\n' | grep -vE "^($2)" | tr '\n' ' ')
  fi
}

filter_known_services() {
  filter_and_add_service "arkime" "arkimeviewer|arkimecapture"
  omit_service "qemu-guest-agent" "open-vm-tools|vmtoolsd"
  omit_service "open-vm-tools" "vmtoolsd"
  omit_service "keepalived" "ipvsadm"
  omit_service "mariadb" "mysql"
  omit_service "mysql" "mysqld"
}

get_services() {
  get_services_systemctl
  filter_known_services
}

print_services_in_column() {
  COLUMNS=3

  out=""
  i=0
  for service in $(echo "$services" | tr ' ' '\n' | sort); do
    service_status=$(systemctl is-active "$service")
    color=$R
    if [ "$service_status" = "active" ]; then
      color=$G
    fi
    out="${out}${service}:,${color}${service_status}${undim},"
    if [ $((($i+1) % $COLUMNS)) -eq 0 ]; then
      out="${out}\n"
    fi
    i=$(expr $i + 1)
  done
  if ! [ -z "$out" ]; then
    echo -e "\n${W}Services:"
    printf "$out" | column -ts $',' | sed -e 's/^/  /'
  fi
}

print_services_plain() {
  for service in $(echo "$services" | tr ' ' '\n' | sort); do
    service_status=$(systemctl is-active "$service")
    color=$R
    if [ "$service_status" = "active" ]; then
      color=$G
    fi
    out="${service}: ${color}${service_status}${undim}"
    echo -e "$out"
  done
}

print_services() {
  if command -v systemctl >/dev/null 2>&1; then
    get_services
    print_services_in_column
  fi
}

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

new_update_str="\n${Y}${dim}New zn-motd update detected. Run \"motd -U\" with root privileges to update the MOTD."

update_tmp_ver() {
  update_tmp_pre $VER_FILE_prefix
  download "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/src/00-_ver" "$TMP_DIR/$VER_FILE"
  update_tmp_post $VER_FILE_prefix
  remote_motd_ver=$(cat $TMP_DIR/$VER_FILE)
}

update_motd() {
  update_tmp_ver
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "$new_update_str"
  else
    if command -v curl >/dev/null 2>&1; then
      curl -s https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
    fi
  fi
}

daily_update_motd() {
  if [ -f $TMP_DIR/$VER_FILE ]; then
    remote_motd_ver=$(cat $TMP_DIR/$VER_FILE)
    if [ "$remote_motd_ver" != "$motd_ver" ]; then
      if [ "$(id -u)" -ne 0 ]; then
        echo -e "$new_update_str"
      else
        update_motd
      fi
    fi
  else
    update_tmp_ver
    daily_update_motd
  fi
}

print_motd() {
  print_sysinfo
  print_res_usage
  print_services
  print_active_logins
  print_reboot_check
  daily_update_motd
}

if [ -z "$1" ]; then
  print_motd
elif [ "$1" = "--version" ] || [ "$1" = "-V" ]; then
  echo "zn-motd v$motd_ver"
elif [ "$1" = "--service" ] || [ "$1" = "-S" ]; then
  get_services
  print_services_plain
elif [ "$1" = "--info" ] || [ "$1" = "-I" ]; then
  print_sysinfo
elif [ "$1" = "--resources" ] || [ "$1" = "-R" ]; then
  print_res_usage
elif [ "$1" = "--who" ] || [ "$1" = "-W" ]; then
  print_active_logins
elif [ "$1" = "--reboot" ] || [ "$1" = "-B" ]; then
  print_reboot_check
elif [ "$1" = "--silent" ]; then
  :
elif [ "$1" = "--update" ] || [ "$1" = "-U" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "This option requires sudo privileges."
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
  fi
  update_motd
else
  echo "Usage: motd [OPTION]"
  echo "If no option is provided, the MOTD will be displayed."
  echo ""
  echo "Options:"
  echo "  --help, -h            Show help message"
  echo "  --version, -V         Display the version of zn-motd"
  echo "  --update, -U          Update zn-motd to the latest version"
  echo "  --info, -I            Display system information"
  echo "  --resources, -R       Display resource usage"
  echo "  --service, -S         Display service"
  echo "  --who, -W             Display active logins"
  echo "  --reboot, -B          Display reboot required"
fi