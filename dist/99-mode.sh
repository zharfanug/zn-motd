if ! [[ -n "$1" ]]; then
  print_motd
elif [[ "$1" == "--version" || "$1" == "-V" ]]; then
  echo "zn-motd v$motd_ver"
elif [[ "$1" == "--version-only" || "$1" == "-VV" ]]; then
  echo $motd_ver
elif [[ "$1" == "--service" || "$1" == "-S" ]]; then
  get_services
  print_services_plain
elif [[ "$1" == "--update" || "$1" == "-U" ]]; then
  update_version
else
  echo "Usage: zn-motd [OPTION]"
  echo "If no option is provided, the MOTD will be displayed."
  echo ""
  echo "Options:"
  echo "  --version, -V         Display the version of zn-motd"
  echo "  --version-only, -VV   Display the version number only"
  echo "  --service, -S         Display the current service status"
  echo "  --update, -U          Update zn-motd to the latest version"
  echo "  --help, -h            Show this help message"
fi

