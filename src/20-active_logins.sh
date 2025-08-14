show_active_logins() {
  echo -e "\n${W}Active Logins:"

  printf "  %-19s | %-10s | %-17s | %s\n" "User" "Terminal" "Session Start" "From"
  prev_username="user"
  prev_time="time"
  prev_ip="ip"
  while IFS= read -r line; do
    who_str=""
    who_invalid=0
    same_probs=0
    if [ -z "$line" ]; then
      continue
    fi

    username=$(echo "$line" | awk '{print $1}')
    if ! echo "$username" | grep -Eq "^[a-zA-Z][a-zA-Z0-9_-]{2,31}$"; then
      who_invalid=$((who_invalid + 1))
    else
      if [ "$username" = "$prev_username" ]; then
        same_probs=$((same_probs + 1))
      fi
      prev_username=$username
    fi

    login_terminal=$(echo "$line" | grep -Eo "(tty[v]?[0-9]+|pts/[0-9]+|console|seat[0-9]+)")
    if [ -z "$login_terminal" ]; then
      login_terminal2=$(echo "$line" | grep -Eo "(\s+ssh[d]?\s+)")
      if [ -z "$login_terminal2" ]; then
        login_terminal="unknown"
      else
        set -- $login_terminal2
        login_terminal2=$*
        login_terminal=$login_terminal2
      fi
    fi

    login_ip=$(echo "$line" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}")
    if [ -z "$login_ip" ]; then
      login_ip="-"
    fi
    if [ "$login_ip" = "$prev_ip" ]; then
      same_probs=$((same_probs + 1))
    fi
    prev_ip=$login_ip

    login_time=$(echo "$line" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}')
    if [ -z "$login_time" ]; then
      who_invalid=$((who_invalid + 1))
    else
      if [ "$login_time" = "$prev_time" ]; then
        same_probs=$((same_probs + 1))
      fi
      prev_time=$login_time
    fi

    who_str="$(printf "  %-19s | %-10s | %-17s | %s\n" "$username" "$login_terminal" "$login_time" "$login_ip")"
    if [ "$who_invalid" -eq 0 ]; then
      if [ "$same_probs" -ne 3 ]; then
        echo "$who_str"
      fi
    else
      echo $line
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

