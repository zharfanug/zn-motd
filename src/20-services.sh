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

