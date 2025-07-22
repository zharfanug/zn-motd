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

ver_file="$SRC_DIR/00-_ver"
new_ver="1.0.0_$(date +'%Y%m%d%H%M')"
echo -n "$new_ver" > "$ver_file"
build_motd
git checkout --orphan latest_branch
git add .
git commit -am "Initial commit"
git branch -D main
git branch -m main
git push -f origin main

git tag -d latest
git tag latest
git push origin latest --force