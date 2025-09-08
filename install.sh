#!/bin/sh

STARTUP_DIR=/etc/profile.d
MOTD=zn-motd.sh

# colors
W="\e[0;39m"
R="\e[1;31m"
G="\e[1;32m"
Y="\e[1;33m"
dim="\e[2m"
undim="\e[0m"

TMP_DIR="/tmp/.zn-motd"

repo_update=0

# Ask for sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "Install/update zn-motd requires sudo privileges."
  exec sudo "$0" "$@"
  exit
fi

if command -v sudo >/dev/null 2>&1; then
  rm() { sudo rm -f "$@" || exit 1; }
  mv() { sudo mv -f "$@" || exit 1; }
  ln() { sudo ln "$@" || exit 1; }
  chmod() { sudo chmod "$@" || exit 1; }
  curl() { sudo curl "$@" || exit 1; }
else
  rm() { command rm -f "$@" || exit 1; }
  mv() { command mv -f "$@" || exit 1; }
  ln() { command ln "$@" || exit 1; }
  chmod() { command chmod "$@" || exit 1; }
  curl() { command curl "$@" || exit 1; }
fi

if command -v sudo >/dev/null 2>&1; then
  apt()    { sudo apt -y "$@" || exit 1; }
  yum()    { sudo yum -y "$@" || exit 1; }
  dnf()    { sudo dnf -y "$@" || exit 1; }
  zypper() { sudo zypper -y "$@" || exit 1; }
else
  apt()    { command apt -y "$@" || exit 1; }
  yum()    { command yum -y "$@" || exit 1; }
  dnf()    { command dnf -y "$@" || exit 1; }
  zypper() { command zypper -y "$@" || exit 1; }
fi

do_repo_update() {
  repo_update=1
  if command -v apt >/dev/null 2>&1; then
    apt update
  elif command -v dnf >/dev/null 2>&1; then
    dnf makecache
  elif command -v yum >/dev/null 2>&1; then
    yum makecache
  elif command -v zypper >/dev/null 2>&1; then
    zypper refresh
  else
    repo_update=0
    echo "Error: No supported package manager found (apt, dnf, yum, zypper)"
  fi
}

install_pkg() {
  if [ "$repo_update" -eq 0 ]; then
    do_repo_update
  fi

  if command -v apt >/dev/null 2>&1; then
    apt install "$1"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install "$1"
  elif command -v yum >/dev/null 2>&1; then
    yum install "$1"
  elif command -v zypper >/dev/null 2>&1; then
    zypper install "$1"
  else
    echo "Error: No supported package manager found (apt, dnf, yum, zypper)"
    if [ "$2" = "true" ]; then
      exit 1
    fi
  fi
}

install_if_not_exist() {
  is_exist=0
  cmd_name=$1
  pkg_name=$1
  if [ -n "$2" ]; then
    pkg_name=$2
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    message="$Y'$pkg_name' is not installed. Installing it now...$W"
    echo -e >&2 "$message"
    install_pkg $pkg_name true
  fi
}

download_motd() {
  mkdir -p "$TMP_DIR"
  chown nobody:nogroup "$TMP_DIR" >/dev/null 2>&1
  if command -v curl >/dev/null 2>&1; then
    curl -s "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/${MOTD}" -o "$TMP_DIR/${MOTD}"
    chown nobody:nogroup "$TMP_DIR/${MOTD}" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/${MOTD}" -O "$TMP_DIR/${MOTD}"
    chown nobody:nogroup "$TMP_DIR/${MOTD}" >/dev/null 2>&1
  else
    install_if_not_exist curl
    download_motd
  fi
}

remove_cmd() {
  cmd_name=$1
  list_motd=$(which $cmd_name 2>/dev/null)

  if ! [ -z $list_motd ]; then
    while IFS= read -r line; do
      # echo "Command $cmd_name already exists, removing $line"
      rm "$line" >/dev/null 2>&1
      sleep 1
    done <<EOF
$list_motd
EOF
  fi
}

add_cmd() {
  exe_src=$1
  cmd_name=$1
  if [ -n "$2" ]; then
    cmd_name=$2
  fi
  if [ -d "/bin" ]; then
    rm /bin/$cmd_name >/dev/null 2>&1
    ln -s $exe_src /bin/$cmd_name
    chmod +x /bin/$cmd_name
    # echo "Symbolic link created: /bin/$cmd_name -> $exe_src"
  fi
}

install_if_not_exist mpstat sysstat
install_if_not_exist bc
download_motd

if [ -f $STARTUP_DIR/$MOTD ]; then
  excluded_services="$(cat $STARTUP_DIR/$MOTD | grep -E '^excluded_services=' | awk -F'"' '{print $2}')"
  included_services="$(cat $STARTUP_DIR/$MOTD | grep -E '^included_services=' | awk -F'"' '{print $2}')"
  sed -i "s/^excluded_services=.*/excluded_services=\"${excluded_services}\"/" "$TMP_DIR/$MOTD"
  sed -i "s/^included_services=.*/included_services=\"${included_services}\"/" "$TMP_DIR/$MOTD"
fi

remove_cmd "motd"
mv "$TMP_DIR/$MOTD" "$STARTUP_DIR/$MOTD"
add_cmd "$STARTUP_DIR/$MOTD" "motd"
rm -rf "$TMP_DIR" >/dev/null 2>&1
