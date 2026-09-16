#!/bin/bash
# Keyboard teleop inside the container that run.sh started.
# Hold i / , to walk, j / l to turn, Shift+J / Shift+L to step sideways; k stops.
docker exec -it go2 /entrypoint.sh ros2 run teleop_twist_keyboard teleop_twist_keyboard
