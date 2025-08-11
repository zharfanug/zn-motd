# Clean echo from any parameter
if [ -x "/bin/echo" ]; then
  alias echo="/bin/echo"
fi

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -s "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    echo "Command 'curl' or 'wget' not found."
    exit 1
  fi
}

mkdir -p "$TMP_DIR"

update_tmp_pre() {
  FILE_PREFIX=$1
  rm $TMP_DIR/${FILE_PREFIX}* >/dev/null 2>&1
}

update_tmp_post() {
  TMP_FILE_PREFIX=$1
  TMP_FILE=$2
  sleep 1
  chown nobody:nogroup $TMP_DIR/${FILE_PREFIX}* >/dev/null 2>&1
}

