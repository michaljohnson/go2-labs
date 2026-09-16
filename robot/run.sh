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
docker run --rm -it --name go2 \
  --network host --ipc host \
  cas-go2-robot "$@"
