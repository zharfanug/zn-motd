#!/bin/sh

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

cd "$SCRIPT_DIR"
cd ..

SRC_DIR="src"
BUILD_DIR="dev-build"

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

chmod -R +x $BUILD_DIR

$BUILD_DIR/motd.sh
