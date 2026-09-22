#!/bin/bash
# Start the Go2 simulation with one command.
#
#   ./sim/start.sh              # the hall world (lab.sdf)
#   ./sim/start.sh headless     # the bare plane, no sensors
#   ./sim/start.sh stop         # stop everything
#
# The zenoh router and Gazebo run in the background; their output goes to ~/rap/logs/.
# Gazebo's own window opens on the pod's desktop - watch it in the browser. This terminal
# is left running teleop, so you can drive the dog straight away:
#
#   i / ,  walk forwards / backwards      j / l  turn      k  stop      Ctrl+C  quit
#
# Quitting teleop leaves the simulation running; `./sim/start.sh stop` ends it.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HOME/rap/cas/go2_ws"
WORLDS="$WS/src/unitree_go2_ros2/unitree_go2_description/worlds"
LOGS="$HOME/rap/logs"

source "$HERE/env.sh"

if [ "$1" = "stop" ]; then
  pkill -f "unitree_go2_launch" 2>/dev/null || true
  pkill -f "gz sim" 2>/dev/null || true
  pkill -f rmw_zenohd 2>/dev/null || true
  echo "stopped"
  exit 0
fi

[ -d "$WS/install" ] || { echo "No workspace in $WS - run ./sim/setup.sh first"; exit 1; }

WORLD="$WORLDS/${1:-lab}.sdf"
[ -f "$WORLD" ] || WORLD="$WORLDS/headless.sdf"
mkdir -p "$LOGS"

# The router first: nodes that start before it do not find each other.
if ! pgrep -f rmw_zenohd >/dev/null; then
  nohup ros2 run rmw_zenoh_cpp rmw_zenohd > "$LOGS/router.log" 2>&1 &
  sleep 3
fi

if ! pgrep -f unitree_go2_launch >/dev/null; then
  echo "starting Gazebo with $(basename "$WORLD") - the window opens on the desktop"
  nohup ros2 launch unitree_go2_sim unitree_go2_launch.py rviz:=false world:="$WORLD" \
    > "$LOGS/sim.log" 2>&1 &
  # Gazebo and the controllers need about this long before the dog reacts.
  for i in $(seq 20); do printf '.'; sleep 2; done; echo
fi

if ! pgrep -f "gz sim" >/dev/null; then
  echo "Gazebo did not start. Last lines of $LOGS/sim.log:"
  tail -15 "$LOGS/sim.log"
  exit 1
fi

echo "Logs: $LOGS/sim.log and $LOGS/router.log"
echo "Driving the dog - i / , walk, j / l turn, k stop, Ctrl+C to quit."
exec ros2 run teleop_twist_keyboard teleop_twist_keyboard
