#!/bin/bash
# Start the Go2 simulation in the pod: one command instead of three terminals.
#
#   ./sim/start.sh              # the hall world (lab.sdf)
#   ./sim/start.sh headless     # the bare plane
#   ./sim/start.sh stop         # close everything again
#
# It opens a tmux session with one window per piece:
#
#   0 router    zenoh, the middleware every node talks through - must start first
#   1 sim       Gazebo: physics, the dog, the world. Its window opens on the desktop
#   2 teleop    drive the dog: i / , to walk, j / l to turn, k to stop
#
# Switch windows with Ctrl-b then the number, detach with Ctrl-b then d.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HOME/rap/cas/go2_ws"
WORLDS="$WS/src/unitree_go2_ros2/unitree_go2_description/worlds"
SESSION="go2"

if [ "$1" = "stop" ]; then
  tmux kill-session -t "$SESSION" 2>/dev/null && echo "stopped" || echo "nothing was running"
  exit 0
fi

command -v tmux >/dev/null || { echo "tmux is missing: sudo apt install -y tmux"; exit 1; }
[ -d "$WS/install" ] || { echo "No workspace in $WS - run ./sim/setup.sh first"; exit 1; }

WORLD="$WORLDS/${1:-lab}.sdf"
[ -f "$WORLD" ] || WORLD="$WORLDS/headless.sdf"   # lab.sdf only exists after setup.sh

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Already running - attaching. './sim/start.sh stop' closes it."
  exec tmux attach -t "$SESSION"
fi

# ROS, the workspace, zenoh and DISPLAY - see env.sh for why each is needed.
PRELUDE="source $HERE/env.sh"

tmux new-session -d -s "$SESSION" -n router
tmux send-keys -t "$SESSION:router" "$PRELUDE; ros2 run rmw_zenoh_cpp rmw_zenohd" C-m
sleep 3   # nodes that start before the router don't find each other

tmux new-window -t "$SESSION" -n sim
tmux send-keys -t "$SESSION:sim" "$PRELUDE; ros2 launch unitree_go2_sim unitree_go2_launch.py \
  rviz:=false world:=$WORLD \
  disable_camera:=true disable_d455:=true disable_lidar_l1:=true disable_velodyne_lidar:=true" C-m
sleep 20  # Gazebo and the controllers need about this long before teleop is useful

tmux new-window -t "$SESSION" -n teleop
tmux send-keys -t "$SESSION:teleop" "$PRELUDE; ros2 run teleop_twist_keyboard teleop_twist_keyboard" C-m

echo "World: $(basename "$WORLD")"
echo "The Gazebo window opens on the pod's desktop - look at it in the browser."
tmux attach -t "$SESSION"
