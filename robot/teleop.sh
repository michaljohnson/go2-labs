#!/bin/bash
# Keyboard teleop inside the container that run.sh started.
# Hold i / , to walk, j / l to turn, Shift+J / Shift+L to step sideways; k stops.
docker exec -it go2 /entrypoint.sh ros2 run teleop_twist_keyboard teleop_twist_keyboard

# Recording and replaying a bag works the same way, in a third terminal:
#   docker exec -it go2 /entrypoint.sh ros2 bag record -o my_route /cmd_vel /odom /sportmodestate
#   docker exec -it go2 /entrypoint.sh ros2 bag play my_route
# Bags land in ../bags on the Jetson (the repo folder), not inside the container.
