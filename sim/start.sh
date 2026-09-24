#!/bin/bash
# Start the Go2 simulation with one command.
#
#   ./sim/start.sh              # the hall world (lab.sdf)
#   ./sim/start.sh headless     # the bare plane, no sensors
#   ./sim/start.sh stop         # stop everything
#
# TMUX=1 puts the router, the simulation and teleop in one tmux session instead of the
# background, so you can watch each of them:
#
#   TMUX=1 ./sim/start.sh
#   tmux attach -t sim          # Ctrl-b then 0/1/2 to switch, Ctrl-b then d to detach
#
# Without it, the router and Gazebo go to the background with their output in ~/rap/logs/,
# and this terminal is left running teleop so you can drive straight away:
#
#   i / ,  walk forwards / backwards      j / l  turn      k  stop      Ctrl+C  quit
#
# Gazebo's own window opens on the pod's desktop - watch it in the browser either way.
# Quitting teleop leaves the simulation running; `./sim/start.sh stop` ends it.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HOME/rap/cas/go2_ws"
WORLDS="$WS/src/unitree_go2_ros2/unitree_go2_description/worlds"
LOGS="$HOME/rap/logs"

source "$HERE/env.sh"

if [ "$1" = "stop" ]; then
  tmux kill-session -t sim 2>/dev/null || true
  # SIGINT first: ros2 launch shuts its own nodes down when interrupted. Killing the launch
  # outright leaves ekf_node, the ros_gz bridges and the controller spawners running - they
  # then meet the next Gazebo's clock restarting at zero, flood the log with "Detected jump
  # back in time", and the new controllers never spawn. The dog lies there while everything
  # around it looks healthy.
  pkill -INT -f unitree_go2_launch 2>/dev/null || true
  for i in $(seq 10); do pgrep -f unitree_go2_launch >/dev/null || break; sleep 1; done

  # then sweep whatever outlived it
  for p in unitree_go2_launch ekf_node parameter_bridge ros_gz spawner \
           robot_state_publisher "gz sim" rmw_zenohd; do
    pkill -f "$p" 2>/dev/null || true
  done
  sleep 1

  left=$(pgrep -af "unitree_go2|ekf_node|parameter_bridge|gz sim|rmw_zenohd" 2>/dev/null | grep -v pgrep || true)
  if [ -n "$left" ]; then echo "still running:"; echo "$left"; else echo "stopped"; fi
  exit 0
fi

[ -d "$WS/install" ] || { echo "No workspace in $WS - run ./sim/setup.sh first"; exit 1; }

WORLD="$WORLDS/${1:-lab}.sdf"
[ -f "$WORLD" ] || WORLD="$WORLDS/headless.sdf"
mkdir -p "$LOGS"

# Only rmw_zenoh needs a router, and the simulation no longer asks for one - it runs on the
# default middleware. The block stays for anyone who sets RMW_IMPLEMENTATION=rmw_zenoh_cpp.
#
# The router has to be up before the nodes: ones that start first never find each other, and
# waiting a fixed three seconds used to hide a router that had died on startup, leaving the
# spawners to fail with "Unable to connect to a Zenoh router" while this script blamed
# Gazebo. So wait for the port, then say so.
if [ "$RMW_IMPLEMENTATION" = "rmw_zenoh_cpp" ]; then
  if ! pgrep -f rmw_zenohd >/dev/null; then
    nohup ros2 run rmw_zenoh_cpp rmw_zenohd > "$LOGS/router.log" 2>&1 &
  fi
  for i in $(seq 15); do
    (exec 3<>/dev/tcp/127.0.0.1/7447) 2>/dev/null && { exec 3<&-; break; }
    sleep 1
  done
  if ! (exec 3<>/dev/tcp/127.0.0.1/7447) 2>/dev/null; then
    echo "The zenoh router is not listening on 7447. Last lines of $LOGS/router.log:"
    tail -15 "$LOGS/router.log"
    exit 1
  fi
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

if [ -n "$TMUX_MODE" ] || [ "$TMUX" = "1" ]; then
  command -v tmux >/dev/null || { echo "tmux is missing: sudo apt install -y tmux"; exit 1; }
  if tmux has-session -t sim 2>/dev/null; then
    echo "Already a 'sim' session - attaching."
    exec tmux attach -t sim
  fi
  # The router and Gazebo are already running in the background; give them windows that
  # follow their logs, so one session shows everything.
  tmux new-session -d -s sim -n router "tail -f $LOGS/router.log"
  tmux new-window  -t sim: -n sim      "tail -f $LOGS/sim.log"
  tmux new-window  -t sim: -n teleop   "ros2 run teleop_twist_keyboard teleop_twist_keyboard; read"
  echo "tmux session 'sim' - tmux attach -t sim (Ctrl-b 0/1/2, Ctrl-b d to detach)"
  exit 0
fi

echo "Driving the dog - i / , walk, j / l turn, k stop, Ctrl+C to quit."
exec ros2 run teleop_twist_keyboard teleop_twist_keyboard
