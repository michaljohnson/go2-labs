#!/bin/bash
# Start the Go2 robot side on the Jetson.
#
#   ./run.sh              the /cmd_vel -> sport-mode bridge (Ctrl+C stops the dog)
#   ./run.sh telemetry    republish the dog's odometry and mode for the operator
#   ./run.sh bash         a shell with ROS and the Unitree messages loaded
#   ./run.sh ros2 topic list        any one-off command, run verbatim
#
# Which dog this is comes from NAMESPACE, or from /etc/default/go2-dog so that the
# identity belongs to the machine and nobody types it again:
#
#   echo 'NAMESPACE=dog1' | sudo tee /etc/default/go2-dog
#
# It is applied as a ROS remap, -r __ns:=/dog1. ROS_NAMESPACE is a ROS 1 variable and has
# no effect in ROS 2 - it sat in these scripts for a day looking like it worked.
#
# --network/--ipc host: DDS in the container must reach the dog's network
#   (192.168.123.x) directly, discovery needs both.
# ROS_DOMAIN_ID stays unset (= 0): the dog publishes on domain 0.
# -v bags: the container is --rm, so anything written inside is gone when it stops.
#   ./bags on the Jetson appears as /bags inside - rosbag files survive there.
# -v robot: the scripts are mounted, not baked in, so a fix ships by scp.
if [ -z "$NAMESPACE" ] && [ -f /etc/default/go2-dog ]; then . /etc/default/go2-dog; fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO/bags"

NS_ARGS=()
[ -n "$NAMESPACE" ] && NS_ARGS=(--ros-args -r __ns:=/"${NAMESPACE#/}")

case "${1:-}" in
  "")         NAMED=(--name go2);           CMD=(python3 /robot/go2_cmd_vel_bridge.py "${NS_ARGS[@]}") ;;
  telemetry)  NAMED=(--name go2-telemetry); CMD=(python3 /robot/go2_telemetry.py     "${NS_ARGS[@]}") ;;
  # Anything else runs verbatim and unnamespaced - `ros2 topic list` would choke on
  # --ros-args, and a one-off question should not claim the bridge's container name.
  *)          NAMED=();                     CMD=("$@") ;;
esac

docker run --rm -it "${NAMED[@]}" \
  --network host --ipc host \
  -v "$REPO/bags":/bags -v "$REPO/robot":/robot \
  -w /bags \
  cas-go2-robot "${CMD[@]}"
