#!/bin/sh

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

cd "$SCRIPT_DIR"
cd ..

SRC_DIR="src"
BUILD_DIR="dev-build"

build_motd() {
  predefined_excluded_services=""
  for line in $(cat $SRC_DIR/00-predefined_excluded_services); do
    if [ -z "$predefined_excluded_services" ]; then
      predefined_excluded_services="$line"
    else
      predefined_excluded_services="$predefined_excluded_services|$line"
    fi
  done

  predefined_excluded_instance_services=""
  for line in $(cat $SRC_DIR/00-predefined_excluded_instance_services); do
    if [ -z "$predefined_excluded_instance_services" ]; then
      predefined_excluded_instance_services="$line"
    else
      predefined_excluded_instance_services="$predefined_excluded_instance_services|$line"
    fi
  done

  mkdir -p $BUILD_DIR
  motd_ver=$(cat "${SRC_DIR}/00-_ver")
  cat $SRC_DIR/*.sh > $BUILD_DIR/motd.sh
  sed -i "s/^predefined_excluded_services=.*/predefined_excluded_services=\"${predefined_excluded_services}\"/" $BUILD_DIR/motd.sh
  sed -i "s/^predefined_excluded_instance_services=.*/predefined_excluded_instance_services=\"${predefined_excluded_instance_services}\"/" $BUILD_DIR/motd.sh
  sed -i "s/^motd_ver=.*/motd_ver=\"${motd_ver}\"/" $BUILD_DIR/motd.sh
  cp "$BUILD_DIR/motd.sh" "zn-motd.sh"
  sha256sum "zn-motd.sh" > "zn-motd.sh.sha256"
}

update_ver() {
  # Change ver
  ver_file="$SRC_DIR/00-_ver"
  current_ver=$(cat "$ver_file")
  current_ver=$(echo "$current_ver" | cut -d'_' -f1)

  # Split version into parts
  ver_parts=$(echo "$current_ver" | tr '.' ' ')  # Replace dots with spaces
  set -- $ver_parts  # Set positional parameters to the version parts

  # Increment the third part of the version
  third_part=$(( $3 + 1 ))

  # Construct the new version
  new_ver="$1.$2.$third_part"
  new_ver="${new_ver}_$(date +'%Y%m%d%H%M')"

  echo -n "$new_ver" > "$ver_file"
}

update_ver
build_motd

# Default commit message
commit_msg="Minor adjustments"

# Check if the first argument is provided
if [ -n "$1" ]; then
  commit_msg="$1"
fi

git add .
git commit -m "$commit_msg"
git push origin main

git tag -d latest
git tag latest
git push origin latest --force