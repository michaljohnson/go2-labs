#!/bin/bash
# Build the Go2 simulation workspace in the RAP pod.
#
#   ./sim/setup.sh                        # clone + build, about 10 minutes
#   ./sim/setup.sh --prebuilt <url|file>  # unpack a built workspace, about a minute
#
# Puts the workspace in ~/rap (the only storage that survives a pod restart) and pins the
# simulation to a fixed commit, so an upstream change can't break a lab mid-term.
#
# The prebuilt archive comes from sim/pack_workspace.sh. It is built with
# --symlink-install, so it only works when unpacked to the same path it was built at -
# true for every pod, since they all use /home/ros/rap.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"   # absolute: the script cds later, relative paths would break
WS="$HOME/rap/cas/go2_ws"
SIM_REPO="https://github.com/khaledgabr77/unitree_go2_ros2.git"
SIM_REF="55ff151632a0220bf3ae0c0772392615d86da7a8"   # 2026-09-16

source /opt/ros/jazzy/setup.bash

if [ "$1" = "--prebuilt" ]; then
  SRC="${2:?usage: ./sim/setup.sh --prebuilt <url-or-file>}"
  echo "Go2 simulation (prebuilt) -> $WS"
  mkdir -p "$(dirname "$WS")"
  case "$SRC" in
    http*) wget -qO- "$SRC" | tar xzf - -C "$(dirname "$WS")" ;;
    *)     tar xzf "$SRC" -C "$(dirname "$WS")" ;;
  esac
else
  echo "Go2 simulation -> $WS"
  echo "  $SIM_REPO @ $SIM_REF"
  mkdir -p "$WS/src"
  cd "$WS/src"

  if [ -d unitree_go2_ros2 ]; then
    git -C unitree_go2_ros2 fetch --quiet origin
  else
    git clone --quiet "$SIM_REPO"
  fi
  git -C unitree_go2_ros2 checkout --quiet "$SIM_REF"
fi

# A world without the sensor plugin: it renders, and the pod denies /dev/dri, which kills
# the server. Without sensors the dog walks fine. Then the same world plus a hall to walk in.
python3 "$HERE/patches/make_headless_world.py"
python3 "$HERE/patches/make_lab_world.py"

if [ "$1" != "--prebuilt" ]; then
  # --skip-keys: upstream asks for "unitree_applications", but the package is "unitree_application".
  cd "$WS"
  rosdep install --from-paths src --ignore-src -y --skip-keys unitree_applications
  colcon build --symlink-install
fi

echo
echo "Done. Start it with ./sim/start.sh, or the three terminals in docs/lab1-sim.md."
