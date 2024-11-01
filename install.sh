#!/bin/bash

startup_path=/etc/profile.d
build_filename=zn-motd.sh

# colors
W="\e[0;39m"
R="\e[1;31m"
G="\e[1;32m"
Y="\e[1;33m"
dim="\e[2m"
undim="\e[0m"

repo_update=0

# Ask for sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "This script requires sudo privileges."
  exec sudo "$0" "$@"
  exit
fi

command -v apt >/dev/null 2>&1 && alias apt='sudo apt -y'
command -v yum >/dev/null 2>&1 && alias apt='sudo yum -y'
command -v rm >/dev/null 2>&1 && alias rm='sudo rm -f'
command -v ln >/dev/null 2>&1 && alias ln='sudo ln'
command -v sed >/dev/null 2>&1 && alias ln='sudo sed'
command -v systemctl >/dev/null 2>&1 && alias ln='sudo systemctl'
command -v chmod >/dev/null 2>&1 && alias ln='sudo chmod'

do_repo_update() {
  if [ -f /etc/debian_version ]; then
    apt update
    if [ $? -ne 0 ]; then
      echo -e "${R}Error: Failed to update APT repository.${W}"
      exit 1
    fi
  elif [ -f /etc/redhat-release ]; then
    yum makecache
    if [ $? -ne 0 ]; then
      echo -e "${R}Error: Failed to update YUM repository.${W}"
      exit 1
    fi
  else
    echo -e "${R}Error: OS not supported.${W}"
    exit 1
  fi

  repo_update=1
}

install_pkg() {
  if [ "$repo_update" -eq 0 ]; then
    do_repo_update
  fi
  if [ -f /etc/debian_version ]; then
    apt install -y "$1"
    if [ $? -ne 0 ]; then
      echo -e "${R}Error: Failed to install package '$1' using APT.${W}"
      exit 1
    fi
  elif [ -f /etc/redhat-release ]; then
    yum install -y "$1"
    if [ $? -ne 0 ]; then
      echo -e "${R}Error: Failed to install package '$1' using YUM.${W}"
      exit 1
    fi
  else
    echo -e "${R}Error: OS not supported.${W}"
    exit 1
  fi
}

install_if_not_exist() {
  is_exist=0
  cmd_name=$1
  pkg_name=$1
  if [[ -n "$2" ]]; then
    pkg_name=$2
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    message="$Y'$pkg_name' is not installed. Installing it now...$W"
    echo -e >&2 "$message"
    install_pkg pkg_name
  fi
}

build_motd() {
  cat dist/10-*.sh > $startup_path/$build_filename
  cat dist/20-*.sh >> $startup_path/$build_filename
  cat dist/80-*.sh >> $startup_path/$build_filename
  cat dist/98-*.sh >> $startup_path/$build_filename
  cat dist/99-*.sh >> $startup_path/$build_filename
  chmod +x $startup_path/$build_filename >/dev/null 2>&1
}

link_to_bin() {
  exe_src=$1
  cmd_name=$1
  if [[ -n "$2" ]]; then
    cmd_name=$2
  fi

  # Check if the command exists
  while command -v "$cmd_name" >/dev/null 2>&1; do
    echo "Command $cmd_name already exists, removing $(command -v $cmd_name)"
    rm "$(command -v "$cmd_name")" >/dev/null 2>&1
    sleep 1  # Optional: Sleep for 1 second to avoid rapid looping
  done

  # Create the symbolic link
  ln -s $exe_src /usr/bin/$cmd_name
  chmod +x /usr/bin/$cmd_name
  echo "Symbolic link created: /usr/bin/$cmd_name -> $exe_src"
}

omit_svc() {
  check_svc=$(echo -e "$all_svc" | grep -E "^($1)")
  if [[ -n "$check_svc" ]]; then
    IFS=',' read -r -a arr2 <<< "$2"
    arr_svc_keywords+=("${arr2[@]}")
    if [[ -n "$3" ]]; then
      IFS=',' read -r -a arr3 <<< "$3"
      arr_custom_svc+=("${arr3[@]}")
    fi
  fi
}

sed_var() {
  sed -i 's/'$1'=""/'$1'="'$2'"/' $startup_path/$build_filename
}

create_common_svc() {
  common_svc=""
  custom_svc=""
  arr_custom_svc=()
  all_svc=$(systemctl list-unit-files --type=service --no-pager --no-legend | grep -vE "(@)")

  omit_svc "qemu-guest-agent" "open-vm-tools,vmtoolsd"
  omit_svc "open-vm-tools" "vmtoolsd"
  omit_svc "mariadb" "mysql"
  omit_svc "mysql" "mysqld"
  omit_svc "arkime" "arkime" "arkimecapture,arkimeviewer"
  
  for svc_keyword in "${arr_svc_keywords[@]}"
  do
    check_svc=$(echo -e "$all_svc" | grep -E "^($svc_keyword)")
    if [[ -n "$check_svc" ]]; then
      common_svc+="${svc_keyword}|"
    fi
  done
  common_svc="${common_svc%|}"
  if [ -n "$common_svc" ]; then
    sed_var "common_svc" "$common_svc"
  fi

  common_atsvc=""
  all_atsvc=$(systemctl list-units --type=service --state=active --no-pager --no-legend | awk '{print $1}' | grep "@")
  for atsvc_keyword in "${arr_atsvc_keywords[@]}"
  do
    check_atsvc=$(echo -e "$all_atsvc" | grep -E "^($atsvc_keyword)")
    if [[ -n "$check_atsvc" ]]; then
      common_atsvc+="${atsvc_keyword}|"
    fi
  done
  common_atsvc="${common_atsvc%|}"
  if [ -n "$common_atsvc" ]; then
    sed_var "common_atsvc" "$common_atsvc"
  fi

  custom_svc=""
  # all_atsvc=$(systemctl list-units --type=service --state=active --no-pager --no-legend | awk '{print $1}' | grep "@")
  for i_custom_svc in "${arr_custom_svc[@]}"
  do
    custom_svc+="${i_custom_svc},"
  done
  custom_svc="${custom_svc%,}"
  if [ -n "$custom_svc" ]; then
    sed_var "custom_svc" "$custom_svc"
  fi
}

check_config() {
  if [ -e ./zn-config ]; then
    source ./zn-config
    sed_var "included_services" $included_services
    sed_var "excluded_services" $excluded_services
  fi
}

insert_ver() {
  motd_ver=$(cat dist/00-ver)
  sed_var "motd_ver" $motd_ver
}

main() {
  install_if_not_exist curl
  install_if_not_exist mpstat sysstat

  build_motd
  link_to_bin $startup_path/$build_filename motd

  readarray -t arr_svc_keywords < dist/00-svc_keywords
  readarray -t arr_atsvc_keywords < dist/00-atsvc_keywords
  create_common_svc
  check_config
  insert_ver
}

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    missing_command+=("$1")
  fi
}

prereq_test() {
  req_commands=(
    "rm" "ln" "chmod"
    "cut" "awk" "sed" "grep"
    "echo" "printf" "cat"
    "sudo" "systemctl" "source"
    "free" "df" "uname" "uptime"
  )

  missing_command=()
  for cmd in "${req_commands[@]}"; do
    check_command $cmd
  done

  if [ ${#missing_command[@]} -ne 0 ]; then
    echo -e "${R}Error: Prerequisite unsatisfied.${W} Missing commands: ${missing_command[*]}"
  else
    main
  fi
}

prereq_test
