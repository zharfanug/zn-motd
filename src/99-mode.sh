# --------------------- 99-mode.sh ---------------------
# This file parses CLI arguments and dispatches which section(s) to print.
# Prints everything (print_motd) when called with no arguments.

print_usage() {
  printf '%s\n' "Usage: $(basename "$0") [OPTION]..."
  printf '\n'
  printf '%s\n' "  --help, -h          show help"
  printf '%s\n' "  --version, -V       show version"
  printf '%s\n' "  --info, -I          show system info"
  printf '%s\n' "  --resources, -R     show resource usage"
  printf '%s\n' "  --service, -S       show service status"
  printf '%s\n' "  --logins, -L        show active logins"
  printf '%s\n' "  --reboot            show reboot check"
  printf '%s\n' "  --update, -U        update to the latest version"
  printf '\n'
  printf '%s\n' "Prints everything if no option is passed."
}

print_version() {
  printf '%s %s\n' "$(basename "$0")" "$motd_ver"
}

if [ "$#" -eq 0 ]; then
  print_motd
else
  for _arg do
    case "$_arg" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --version|-V)
        print_version
        exit 0
        ;;
      --info|-I)
        print_sysinfo
        ;;
      --resources|-R)
        print_res_usage
        ;;
      --service|-S)
        print_services
        ;;
      --logins|-L)
        print_active_logins
        ;;
      --reboot)
        print_reboot_check
        ;;
      --update|-U)
        update_motd
        ;;
      *)
        printf '%s\n' "Unknown option: $_arg. Use --help for usage." >&2
        exit 1
        ;;
    esac
  done
fi
