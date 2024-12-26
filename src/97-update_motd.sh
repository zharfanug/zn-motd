new_update_str="\n${Y}${dim}New zn-motd update detected. Run \"motd -U\" with root privileges to update the MOTD."

update_tmp_ver() {
  update_tmp_pre $VER_FILE_prefix
  download "https://raw.githubusercontent.com/zharfanug/zn-motd/latest/src/00-_ver" "$TMP_DIR/$VER_FILE"
  update_tmp_post $VER_FILE_prefix
  remote_motd_ver=$(cat $TMP_DIR/$VER_FILE)
}

update_motd() {
  update_tmp_ver
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "$new_update_str"
  else
    if command -v curl >/dev/null 2>&1; then
      curl -s https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
    fi
  fi
}

daily_update_motd() {
  if [ -f $TMP_DIR/$VER_FILE ]; then
    remote_motd_ver=$(cat $TMP_DIR/$VER_FILE)
    if [ "$remote_motd_ver" != "$motd_ver" ]; then
      if [ "$(id -u)" -ne 0 ]; then
        echo -e "$new_update_str"
      else
        update_motd
      fi
    fi
  else
    update_tmp_ver
    daily_update_motd
  fi
}

