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

TMP_DIR="/tmp/zn-motd"

repo_update=0

# Ask for sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "Install/update zn-motd requires sudo privileges."
  exec sudo "$0" "$@"
  exit
fi

# echo "Running the install.sh as $(whoami)"

if [ -x "/bin/sudo" ]; then
  [ -x "/bin/apt" ] && alias apt="sudo /bin/apt -y"
  [ -x "/bin/yum" ] && alias yum='sudo /bin/yum -y'
  [ -x "/bin/rm" ] && alias rm='sudo /bin/rm -f'
  [ -x "/bin/mv" ] && alias mv='sudo /bin/mv -f'
  [ -x "/bin/ln" ] && alias ln='sudo /bin/ln'
  [ -x "/bin/chmod" ] && alias chmod='sudo /bin/chmod'
  [ -x "/bin/curl" ] && alias curl='sudo /bin/curl'
else
  [ -x "/bin/apt" ] && alias apt="/bin/apt -y"
  [ -x "/bin/yum" ] && alias yum='/bin/yum -y'
  [ -x "/bin/rm" ] && alias rm='/bin/rm -f'
  [ -x "/bin/mv" ] && alias mv='/bin/mv -f'
  [ -x "/bin/ln" ] && alias ln='/bin/ln'
  [ -x "/bin/chmod" ] && alias chmod='/bin/chmod'
  [ -x "/bin/curl" ] && alias curl='/bin/curl'
fi
[ -x "/bin/echo" ] && alias echo='/bin/echo'

do_repo_update() {
  [ -x "/bin/apt" ] && apt update
  [ -x "/bin/yum" ] && yum makecache
  repo_update=1
}

install_pkg() {
  if [ "$repo_update" -eq 0 ]; then
    do_repo_update
  fi
  [ -x "/bin/apt" ] && apt install $1
  [ -x "/bin/yum" ] && yum install $1
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
    install_pkg $pkg_name
  fi
}

download_motd() {
  if command -v curl >/dev/null 2>&1; then
    mkdir -p "$TMP_DIR"
    chmod 777 "$TMP_DIR"
    curl -s "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/${MOTD}" -o "$TMP_DIR/${MOTD}"
    chmod 666 "$TMP_DIR/${MOTD}" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    mkdir -p "$TMP_DIR"
    chmod 777 "$TMP_DIR"
    wget -q "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/${MOTD}" -O "$TMP_DIR/${MOTD}"
    chmod 666 "$TMP_DIR/${MOTD}" >/dev/null 2>&1
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