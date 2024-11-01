print_usage() {
  usage_used=$2
  usage_used_h=$3
  usage_total=$4
  usage_total_h=$5
  usage_used_ratio=$(( usage_used * 10000 / usage_total ))
  if (( usage_used_ratio < 10 )); then
    usage_used_ratio="0$usage_used_ratio"
  fi
  usage_used_percent="${usage_used_ratio%??}.${usage_used_ratio: -2}"
  if (( usage_used_ratio < 100 )); then
    usage_used_percent="0$usage_used_percent"
  fi
  if (( usage_used_ratio <= (warn_usage * 100) )); then
    usage_color=$G
  elif (( usage_used_ratio <= (max_usage * 100) )); then
    usage_color=$Y
  else
    usage_color=$R
  fi
  
  if [[ "${1}" == "Memory" ]]; then
    printf "${W}  %-*s: ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h})\n" "$cs" "${1}"
  elif [[ "${1}" == "DiskRoot" ]]; then
    printf "${W}  %-*s: ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h}) (/)\n" "$cs" "Disk"
  elif [[ "${1}" == "DiskOther" ]]; then
    padding=$(printf "%*s" $(($cs + 3)) "") # +2 for ": "
    printf "${W}%s ${usage_color}${usage_used_percent}%%${W} (${usage_color}${usage_used_h}${W} / ${usage_total_h}) (${6})\n" "$padding"
  fi
}

print_cpu_usage() {
  # Fetch CPU Usage
  cpu_idle=$(mpstat 1 1 | awk '/Average:/ {print $NF}')
  cpu_idle=${cpu_idle//./}
  cpu_used_ratio=$((10000 - $cpu_idle))
  cpu_used_percent="${cpu_used_ratio%??}.${cpu_used_ratio: -2}"
  if (( cpu_idle == 10000 )); then
    cpu_used_percent="0.00"
  elif (( cpu_used_ratio < 100 )); then
    cpu_used_percent="0$cpu_used_percent"
  fi

  if (( cpu_used_ratio <= (warn_usage * 100) )); then
    cpu_color=$G
  elif (( cpu_used_ratio <= (max_usage * 100) )); then
    cpu_color=$Y
  else
    cpu_color=$R
  fi
  # get processors
  PROCESSOR_COUNT=`grep -ioP 'processor\t:' /proc/cpuinfo | wc -l`
  printf "${W}  %-*s: ${cpu_color}%s${W} %s\n" "$cs" "CPU" "${cpu_used_percent}%" "($PROCESSOR_COUNT CPU)"
}

print_mem_usage() {
  # Fetch Memory Usage
  memory_info=$(free -b | grep Mem)
  memory_info_h=$(free -h | grep Mem)
  memory_used=$(echo "$memory_info" | awk '{print $3}')
  memory_used_h=$(echo "$memory_info_h" | awk '{print $3}')
  memory_total=$(echo "$memory_info" | awk '{print $2}')
  memory_total_h=$(echo "$memory_info_h" | awk '{print $2}')
  print_usage "Memory" $memory_used $memory_used_h $memory_total $memory_total_h
}

print_disk_usage() {
  # Fetch Disk Usage
  disk_root_info=$(df / | awk 'NR==2 {print $3, $2, $5}')
  disk_root_info_h=$(df / -h | awk 'NR==2 {print $3, $2, $5}')
  disk_root_used=$(echo "$disk_root_info" | awk '{print $1}')
  disk_root_used_h=$(echo "$disk_root_info_h" | awk '{print $1}')
  disk_root_total=$(echo "$disk_root_info" | awk '{print $2}')
  disk_root_total_h=$(echo "$disk_root_info_h" | awk '{print $2}')
  print_usage "DiskRoot" $disk_root_used $disk_root_used_h $disk_root_total $disk_root_total_h

  disks=$(df --output=target -x tmpfs -x devtmpfs | tail -n +2 | grep -vE '^(/boot|/snap)' | grep -vE '^(/)$')
  if [[ -n "${disks}" ]]; then
    while read -r line; do
      disk_info=$(df $line | awk 'NR==2 {print $3, $2, $5}')
      disk_info_h=$(df $line -h | awk 'NR==2 {print $3, $2, $5}')
      disk_used=$(echo "$disk_info" | awk '{print $1}')
      disk_used_h=$(echo "$disk_info_h" | awk '{print $1}')
      disk_total=$(echo "$disk_info" | awk '{print $2}')
      disk_total_h=$(echo "$disk_info_h" | awk '{print $2}')
      if [[ "$disk_used" != "$disk_root_used" ]]; then
        if [[ "$disk_total" != "$disk_root_total" ]]; then
          print_usage "DiskOther" $disk_used $disk_used_h $disk_total $disk_total_h $line
        fi
      fi
    done <<< "$disks"
  fi
}


print_res_usage() {
  echo -e "\n${W}Resources Usage:"
  print_cpu_usage
  print_mem_usage
  print_disk_usage
}

