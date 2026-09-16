#!/bin/bash
# Load ROS and the Unitree messages, point CycloneDDS at the port that leads to
# the dog, then run the given command.
source /opt/ros/$ROS_DISTRO/setup.bash
source /ws/install/setup.bash

# The port to the dog is the one with a 192.168.123.x address (enP8p1s0 on the
# lab Jetson, enx... on a laptop with a USB dongle). GO2_IFACE overrides it.
iface="${GO2_IFACE:-$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.123\./ {print $2; exit}')}"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
if [ -n "$iface" ]; then
  export CYCLONEDDS_URI="<CycloneDDS><Domain><General><Interfaces><NetworkInterface name=\"$iface\" priority=\"default\" multicast=\"default\" /></Interfaces></General></Domain></CycloneDDS>"
else
  echo "entrypoint: no 192.168.123.x address found - is the dog's network connected? (set GO2_IFACE to choose a port)" >&2
fi

exec "$@"
