# --------------------- 20-prereq.sh ---------------------
# This file contains prerequisite checks for the script.

require_cmd_list "awk" "grep" "cut" "date"

CURRENT_DATE=$(date +'%Y%m%d')

VER_FILE="${VER_FILE_prefix}${CURRENT_DATE}"
PUB_IP_FILE="${PUB_IP_FILE_prefix}${CURRENT_DATE}"
ASN_FILE="${ASN_FILE_prefix}${CURRENT_DATE}"
