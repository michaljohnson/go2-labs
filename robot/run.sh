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
docker run --rm -it --name go2 \
  --network host --ipc host \
  -v "$(cd "$(dirname "$0")/.." && pwd)/bags":/bags \
  -w /bags \
  cas-go2-robot "$@"
