#!/bin/bash
# Build the Go2 simulation workspace in the RAP pod.
#
#   ./sim/setup.sh
#
# Puts the workspace in ~/rap (the only storage that survives a pod restart) and pins the
# simulation to a fixed commit, so an upstream change can't break a lab mid-term.
# The apt packages do NOT survive a restart - run this again afterwards.
set -e

WS="$HOME/rap/cas/go2_ws"
SIM_REPO="https://github.com/khaledgabr77/unitree_go2_ros2.git"
SIM_REF="55ff151632a0220bf3ae0c0772392615d86da7a8"   # 2026-09-16

echo "Go2 simulation -> $WS"
echo "  $SIM_REPO @ $SIM_REF"

source /opt/ros/jazzy/setup.bash
mkdir -p "$WS/src"
cd "$WS/src"

if [ -d unitree_go2_ros2 ]; then
  git -C unitree_go2_ros2 fetch --quiet origin
else
  git clone --quiet "$SIM_REPO"
fi
git -C unitree_go2_ros2 checkout --quiet "$SIM_REF"

# Patch 1: the launch file hard-codes the GUI start; the pod needs a server-only Gazebo.
# The window is attached separately with `gz sim -g` (see docs/lab1-sim.md).
launch="$WS/src/unitree_go2_ros2/unitree_go2_sim/launch/unitree_go2_launch.py"
grep -q ", ' -r -s'\]" "$launch" || sed -i "s/, ' -r'\]/, ' -r -s']/" "$launch"

# Patch 2: a world without the sensor plugin. It renders, and the pod denies /dev/dri,
# which kills the server. Without sensors the dog walks fine.
python3 "$(dirname "$0")/patches/make_headless_world.py"

# Same world plus static obstacles, so a walking dog is visibly going somewhere.
python3 "$(dirname "$0")/patches/make_lab_world.py"

# --skip-keys: upstream asks for "unitree_applications", but the package is "unitree_application".
cd "$WS"
rosdep install --from-paths src --ignore-src -y --skip-keys unitree_applications

colcon build --symlink-install

echo
echo "Done. Start it with the four terminals in docs/lab1-sim.md."
