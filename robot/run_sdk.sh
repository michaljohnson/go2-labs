#!/bin/bash
# Run the SDK bridge container on the Jetson.
#
#   ./robot/run_sdk.sh                                  # shell inside the container
#   ./robot/run_sdk.sh --dry-run                        # bridge, logs commands, sends nothing
#   IFACE=eth0 ROUTER=tcp/192.168.0.135:7447 ./robot/run_sdk.sh
#
# IFACE     the interface facing the dog; found by its 192.168.123.x address when unset
# ROUTER    where the zenoh router is; omit for a local one
# DOMAIN    which robot this is; the simulation is 0, so a dog gets its own (default 5)
# ZENOH_USER, ZENOH_PASSWORD  credentials, when the router requires them
# NAMESPACE one dog among several: NAMESPACE=dog1 listens on /dog1/cmd_vel instead of
#           /cmd_vel. Leave it empty and every dog in the domain follows the same topic -
#           which is what you want when they should all do the same thing.
#
# --network host: the SDK needs the dog's network, and zenoh needs to reach the router.
# The working Humble image (cas-go2-robot) is untouched; both can exist side by side, but
# do not run both against the same dog at once.
#
# -v like run.sh: the container is --rm, so ./bags keeps rosbags and ./tools makes
# latency_probe.py runnable inside without baking it into the image.
set -e

IMAGE="${IMAGE:-cas-go2-sdk}"
# The port to the dog is the one with a 192.168.123.x address - enP8p1s0 on the lab
# Jetsons, eth0 or enx... elsewhere. Found the same way the Humble image does it, so
# one command works on every Jetson without a per-machine variable.
IFACE="${IFACE:-$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.123\./ {print $2; exit}')}"
DOMAIN="${DOMAIN:-5}"
NAME="${NAME:-go2-sdk}"
NAMESPACE="${NAMESPACE:-}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO/bags"

docker rm -f "$NAME" >/dev/null 2>&1 || true

if [ "$1" = "--dry-run" ] || [ "$1" = "run" ]; then
  EXTRA=""
  [ "$1" = "--dry-run" ] && EXTRA="--dry-run"
  if [ -z "$IFACE" ]; then
    echo "run_sdk.sh: no 192.168.123.x address - is the dog's cable in?" >&2
    echo "  (set IFACE to force a port)" >&2
    exit 1
  fi
  CMD="python3 /opt/bridge/go2_cmd_vel_sdk_bridge.py --iface $IFACE $EXTRA"
else
  CMD="${*:-bash}"
fi

exec docker run --rm -it --name "$NAME" \
  --network host --ipc host \
  -v "$REPO/bags":/bags -v "$REPO/tools":/tools \
  -e ROUTER="$ROUTER" -e ROS_DOMAIN_ID="$DOMAIN" -e ROS_NAMESPACE="$NAMESPACE" \
  -e ZENOH_USER="$ZENOH_USER" -e ZENOH_PASSWORD="$ZENOH_PASSWORD" \
  "$IMAGE" $CMD
