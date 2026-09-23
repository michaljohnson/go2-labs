#!/bin/bash
# Run the zenoh bridge on the Jetson - the robot end of the ROS/DDS path.
#
#   ROUTER=tcp/1.2.3.4:7448 ./robot/run_bridge.sh
#   ROUTER=... NAMESPACE=dog1 ./robot/run_bridge.sh
#
# ROUTER     where the zenoh router (or the pod's bridge) is. Required.
# NAMESPACE  scope this dog's topics: dog1 -> /dog1/cmd_vel in the pod, while the robot
#            side stays plain /cmd_vel. This is the bridge's own -n, not ROS_NAMESPACE, so
#            nothing on the dog or in any node changes. Tested 23 Sep 2026.
# IFACE      the port facing the dog; found by its 192.168.123.x address when unset
# CONFIG     the allow list; without one the bridge routes every topic it discovers,
#            and the dog publishes ~100 of them including lidar point clouds
#
# The interface is not a detail: CycloneDDS discovery is per-interface, so a bridge bound
# to the wifi never sees the dog's container on the same host. It is enP8p1s0 on the lab
# Jetsons and enx... on one with a USB adapter, which is why this is detected, not typed.
set -e

IMAGE="${IMAGE:-eclipse/zenoh-bridge-ros2dds:1.10.1}"
NAME="${NAME:-zbridge}"
DOMAIN="${DOMAIN:-0}"          # the dog's own domain; the Humble container is here too
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$HERE/bridge_dog.json5}"
IFACE="${IFACE:-$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.123\./ {print $2; exit}')}"

if [ -z "$ROUTER" ]; then
  echo "run_bridge.sh: set ROUTER, e.g. ROUTER=tcp/robopaas.dev:31234" >&2
  exit 1
fi
if [ -z "$IFACE" ]; then
  echo "run_bridge.sh: no 192.168.123.x address - is the dog's cable in?" >&2
  echo "  (set IFACE to force a port)" >&2
  exit 1
fi
# Both paths drive the same dog. Two bridges sending Move to one robot is the one
# failure that can hurt it, so refuse rather than race.
if docker ps --format '{{.Names}}' | grep -qx go2-sdk; then
  echo "run_bridge.sh: the SDK container is running - stop it before using this path" >&2
  exit 1
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true

MOUNT=(); ARGS=()
if [ -f "$CONFIG" ]; then
  MOUNT=(-v "$CONFIG":/c.json5); ARGS+=(-c /c.json5)
else
  echo "run_bridge.sh: no $CONFIG - the bridge will route EVERY topic it finds" >&2
fi
# The bridge wants a leading slash; accept dog1 or /dog1 and normalise.
[ -n "$NAMESPACE" ] && ARGS+=(-n "/${NAMESPACE#/}")

echo "bridge: iface $IFACE, domain $DOMAIN, router $ROUTER${NAMESPACE:+, namespace $NAMESPACE}"

exec docker run --rm -it --name "$NAME" --network host \
  -e ROS_DOMAIN_ID="$DOMAIN" -e ROS_DISTRO=humble \
  -e CYCLONEDDS_URI="<CycloneDDS><Domain><General><Interfaces><NetworkInterface name=\"$IFACE\" priority=\"default\" multicast=\"default\"/></Interfaces></General></Domain></CycloneDDS>" \
  "${MOUNT[@]}" "$IMAGE" client "${ARGS[@]}" -e "$ROUTER" --no-multicast-scouting
