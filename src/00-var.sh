#!/bin/sh

# Service config
excluded_services="" # split by '|' and no space, example: excluded_services="mysql|nginx"
included_services="" # only config if somehow service is excluded by predifined settings

# Predefined service config
predefined_excluded_services=""
predefined_excluded_instance_services=""

motd_ver=""

# Usage threshold
warn_usage=50
max_usage=85

# Spacing
cs=12

# Colors
W="\033[0;39m"     # White
R="\033[1;31m"     # Red
G="\033[1;32m"     # Green
Y="\033[1;33m"     # Yellow
dim="\033[2m"      # Dim text
undim="\033[0m"    # Reset text style

TMP_DIR="/tmp/zn-motd"
CURRENT_DATE=$(date +'%Y%m%d')
VER_FILE_prefix="zn-motd-ver_"
VER_FILE="${VER_FILE_prefix}${CURRENT_DATE}"
PUB_IP_FILE_prefix="zn-motd-pub-ip_"
PUB_IP_FILE="${PUB_IP_FILE_prefix}${CURRENT_DATE}"

