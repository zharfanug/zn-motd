if [ -z "$1" ]; then
  print_motd
elif [ "$1" = "--version" ] || [ "$1" = "-V" ]; then
  echo "zn-motd v$motd_ver"
elif [ "$1" = "--service" ] || [ "$1" = "-S" ]; then
  get_services
  print_services_plain
elif [ "$1" = "--info" ] || [ "$1" = "-I" ]; then
  print_sysinfo
elif [ "$1" = "--resources" ] || [ "$1" = "-R" ]; then
  print_res_usage
elif [ "$1" = "--who" ] || [ "$1" = "-W" ]; then
  print_active_logins
elif [ "$1" = "--reboot" ] || [ "$1" = "-B" ]; then
  print_reboot_check
elif [ "$1" = "--silent" ]; then
  :
elif [ "$1" = "--update" ] || [ "$1" = "-U" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "This option requires sudo privileges."
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
  fi
  update_motd
else
  echo "Usage: motd [OPTION]"
  echo "If no option is provided, the MOTD will be displayed."
  echo ""
  echo "Options:"
  echo "  --help, -h            Show help message"
  echo "  --version, -V         Display the version of zn-motd"
  echo "  --update, -U          Update zn-motd to the latest version"
  echo "  --info, -I            Display system information"
  echo "  --resources, -R       Display resource usage"
  echo "  --service, -S         Display service"
  echo "  --who, -W             Display active logins"
  echo "  --reboot, -B          Display reboot required"
fi