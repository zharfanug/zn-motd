#!/bin/sh

# --------------------- 00-var.sh ---------------------
# This file contains global variables and settings for the script.

# Service config
excluded_services="" # split by '|' and no space, example: excluded_services="mysql|nginx"
included_services="" # only config if somehow service is excluded by predifined settings

# Predefined service config
predefined_excluded_services=""

motd_ver=""

# Repo URL
REPO="zharfanug/zn-motd"
VER_URL="https://raw.githubusercontent.com/${REPO}/latest/VERSION"
INSTALL_URL="https://raw.githubusercontent.com/${REPO}/latest/install.sh"

# Data
TMP_DIR=${HOME:-/tmp}
DATA_DIR_NAME=".zn-motd"
DATA_DIR="${TMP_DIR}/${DATA_DIR_NAME}"
VER_FILE_prefix="remote-ver_"
PUB_IP_FILE_prefix="pub-ip_"
ASN_FILE_prefix="asn-org_"
MOTD_FILE="zn-motd.sh"
STARTUP_DIR="/etc/profile.d"
BIN_FILE="motd"

# Usage threshold
warn_usage=50
max_usage=85

# Spacing
LABEL_WIDTH=12

# Colors
if [ -t 2 ]; then
  ESC=$(printf '\033')

  W="${ESC}[0;39m"
  R="${ESC}[1;31m"
  G="${ESC}[1;32m"
  Y="${ESC}[1;33m"
  B="${ESC}[1;34m"
  DIM="${ESC}[2m"
  C0="${ESC}[0m"
else
  W=
  R=
  G=
  Y=
  B=
  DIM=
  C0=
fi
