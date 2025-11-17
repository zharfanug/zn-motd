print_reboot_check() {
  # Check if reboot is required
  if [ -f /var/run/reboot-required ]; then
    if [ -s /var/run/reboot-required ]; then
      echo -e "\n${W}Reboot Required: ${R}$(cat /var/run/reboot-required) ${W}"
    fi
  fi
}

