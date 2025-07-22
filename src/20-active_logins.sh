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

