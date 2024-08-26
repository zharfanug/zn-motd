get_services() {
  services_pattern="sysstat-"
  if [[ -n "${common_svc}" ]]; then
    services_pattern+="|${common_svc}"
  fi
  if [[ -n "${excluded_services}" ]]; then
    excluded_services_regex=$(echo $excluded_services | sed 's/, /|/g' | sed 's/,/|/g')
    services_pattern+="|${excluded_services_regex}"
  fi
  atservices_pattern="user@"
  if [[ -n "${common_atsvc}" ]]; then
    atservices_pattern+="|${common_atsvc}"
  fi
  if [[ -n "${excluded_services}" ]]; then
    excluded_services_regex=$(echo $excluded_services | sed 's/, /|/g' | sed 's/,/|/g')
    atservices_pattern+="|${excluded_services_regex}"
  fi

  services=($(systemctl list-unit-files --type=service --no-pager --no-legend | grep -vE "(@)" | grep -vE "^(${services_pattern})" | awk '/\.service/ {print substr($1, 1, length($1)-8)}'))
  services+=($(systemctl list-units --type=service --state=active --no-pager --no-legend | awk '{print $1}' | grep "@" | grep -vE "^(${atservices_pattern})" | awk '/\.service/ {print substr($1, 1, length($1)-8)}'))

  if [[ -n "${custom_svc}" ]]; then
    custom_svc=$(echo $custom_svc | sed 's/, /,/g')
    IFS=',' read -r -a temp_arr <<< "$custom_svc"
    services=("${services[@]}" "${temp_arr[@]}")
  fi

  if [[ -n "${included_services}" ]]; then
    included_services=$(echo $included_services | sed 's/, /,/g')
    IFS=',' read -r -a temp_arr <<< "$included_services"
    services=("${services[@]}" "${temp_arr[@]}")
  fi
  # set column width
  COLUMNS=3
  # sort services
  IFS=$'\n' services=($(sort <<<"${services[*]}"))
  unset IFS

  service_status=()
  # get status of all services
  for service in "${services[@]}"; do
    service_status+=($(systemctl is-active "$service"))
  done
}

print_services_in_column() {
  out=""
  for i in ${!services[@]}; do
    # color green if service is active, else red
    if [[ "${service_status[$i]}" == "active" ]]; then
      out+="${services[$i]}:,${G}${service_status[$i]}${undim},"
    else
      out+="${services[$i]}:,${R}${service_status[$i]}${undim},"
    fi
    # insert \n every $COLUMNS column
    if [ $((($i+1) % $COLUMNS)) -eq 0 ]; then
      out+="\n"
    fi
  done
  out+="\n"

  printf "$out" | column -ts $',' | sed -e 's/^/  /'
}

print_services_plain() {
  for i in ${!services[@]}; do
    echo "${services[$i]}: ${service_status[$i]}"
  done
}

print_services() {
  echo -e "\n${W}Services:"

  get_services

  print_services_in_column
}

