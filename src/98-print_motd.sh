# --------------------- 98-print_motd.sh ---------------------
# This file contains functions to retrieve and display motd.

print_motd() {
  print_sysinfo 1
  print_res_usage 1
  print_services 1
  print_active_logins 1
  print_reboot_check 1
  check_update 1
}

