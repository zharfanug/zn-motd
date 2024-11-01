print_active_logins() {
  echo -e "\n${W}Active Logins:"
  who_output=$(who)

  # Print header with dynamic spacing
  printf "  %-19s | %-10s | %-17s | %s\n" "User" "Terminal" "Session Start" "From"

  # Parse and format each line
  while IFS= read -r line; do
    # Extract fields
    username=$(echo "$line" | awk '{print $1}')
    terminal=$(echo "$line" | awk '{print $2}')
    login_time=$(echo "$line" | awk '{print $3, $4}')
    login_from=$(echo "$line" | awk '{print $5}' | tr -d '()')

    if [ "$terminal" == "tty1" ]; then
      login_from="console"
    fi

    # Print formatted output with dynamic spacing
    printf "  %-19s | %-10s | %-17s | %s\n" "$username" "$terminal" "$login_time" "$login_from"
  done <<< "$who_output"
}

