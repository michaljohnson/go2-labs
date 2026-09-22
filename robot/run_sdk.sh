#!/bin/bash
# Run the SDK bridge container on the Jetson.
#
#   ./robot/run_sdk.sh                                  # shell inside the container
#   ./robot/run_sdk.sh --dry-run                        # bridge, logs commands, sends nothing
#   IFACE=eth0 ROUTER=tcp/192.168.0.135:7447 ./robot/run_sdk.sh
#
# IFACE     the interface facing the dog (the one with 192.168.123.x)
# ROUTER    where the zenoh router is; omit for a local one
# DOMAIN    which robot this is; the simulation is 0, so a dog gets its own (default 5)
# NAMESPACE one dog among several: NAMESPACE=dog1 listens on /dog1/cmd_vel instead of
#           /cmd_vel. Leave it empty and every dog in the domain follows the same topic -
#           which is what you want when they should all do the same thing.
#
# --network host: the SDK needs the dog's network, and zenoh needs to reach the router.
# The working Humble image (cas-go2-robot) is untouched; both can exist side by side, but
# do not run both against the same dog at once.
set -e

IMAGE="${IMAGE:-cas-go2-sdk}"
IFACE="${IFACE:-eth0}"
DOMAIN="${DOMAIN:-5}"
NAME="${NAME:-go2-sdk}"
NAMESPACE="${NAMESPACE:-}"

docker rm -f "$NAME" >/dev/null 2>&1 || true

if [ "$1" = "--dry-run" ] || [ "$1" = "run" ]; then
  EXTRA=""
  [ "$1" = "--dry-run" ] && EXTRA="--dry-run"
  CMD="python3 /opt/bridge/go2_cmd_vel_sdk_bridge.py --iface $IFACE $EXTRA"
else
  CMD="${*:-bash}"
fi

exec docker run --rm -it --name "$NAME" \
  --network host --ipc host \
  -e ROUTER="$ROUTER" -e ROS_DOMAIN_ID="$DOMAIN" -e ROS_NAMESPACE="$NAMESPACE" \
  "$IMAGE" $CMD
