#!/bin/bash
# Start the Go2 robot side on the Jetson.
#
#   ./run.sh           the /cmd_vel -> sport-mode bridge (Ctrl+C stops the dog, then the container)
#   ./run.sh bash      a shell with ROS and the Unitree messages loaded
#
# Then drive from a second terminal with ./teleop.sh
#
# --network/--ipc host: DDS in the container must reach the dog's network
#   (192.168.123.x) directly, discovery needs both.
# ROS_DOMAIN_ID stays unset (= 0): the dog publishes on domain 0.
# -v bags: the container is --rm, so anything written inside is gone when it stops.
#   ./bags on the Jetson appears as /bags inside - rosbag files survive there.
mkdir -p "$(dirname "$0")/../bags"

# Only the long-running bridge claims the name "go2", so that `docker exec -it go2 ...`
# reaches it. A one-off question - ./run.sh ros2 topic list - gets an anonymous container
# instead of colliding with the bridge that is currently driving the dog.
NAMED=(); CMD=("$@")
if [ $# -eq 0 ]; then
  NAMED=(--name go2)
  # The image also carries this script, but running the mounted copy means a fix ships by
  # scp instead of an image rebuild on every Jetson.
  CMD=(python3 /robot/go2_cmd_vel_bridge.py)
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# NAMESPACE=dog1 -> /dog1/cmd_vel, /dog1/odom, /dog1/mode. Leave it empty and this dog
# answers to plain /cmd_vel, which is what you want when there is only one.
docker run --rm -it "${NAMED[@]}" \
  --network host --ipc host \
  -e ROS_NAMESPACE="$NAMESPACE" \
  -v "$REPO/bags":/bags -v "$REPO/robot":/robot \
  -w /bags \
  cas-go2-robot "${CMD[@]}"
