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
        if sar -u 2>/dev/null | tail -n 2 > "$sar_tmp_file" 2>/dev/null; then
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

