update_version() {
  old_pwd=$(pwd)

  if cd /opt/zn-motd 2>/dev/null; then
    remote_motd_ver=$(curl -s https://raw.githubusercontent.com/zharfanug/zn-motd/main/dist/00-ver)
    if [ "$remote_motd_ver" != "$motd_ver" ]; then
      git reset --hard main && git pull --rebase origin main && chmod +x install.sh && ./install.sh
    else
      echo "zn-motd is already up to date. Current version: $motd_ver"
    fi
  else
    cd /opt
    git clone https://github.com/zharfanug/zn-motd.git
    cd zn-motd
    chmod +x install.sh
    ./install.sh
  fi
  cd "$old_pwd" || { echo "Failed to return to $old_pwd."; exit 1; }
}

