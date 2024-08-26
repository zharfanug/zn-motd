print_reboot_required() {
  # Check if reboot is required
  if [ -f /var/run/reboot-required ]; then
    echo -e "\n${W}Reboot Required: ${R}$(cat /var/run/reboot-required) ${W}"
  fi
}

