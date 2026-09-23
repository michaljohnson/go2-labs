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

# Three sensor bridges are declared bidirectional (@msg@gz) where every other bridge in the
# file is one-way ([). Gazebo publishes a cloud, the ROS->GZ half sends it straight back,
# and it loops: a 10 Hz lidar measured at 1215 Hz, memory climbing until the pod is OOM-killed.
# One-way is what the other bridges already do.
launch="$WS/src/unitree_go2_ros2/unitree_go2_sim/launch/unitree_go2_launch.py"
sed -i -E "s|(/rgb_image@sensor_msgs/msg/Image)@|\1[|; \
           s|(/unitree_lidar/points@sensor_msgs/msg/PointCloud2)@|\1[|; \
           s|(/velodyne_points/points@sensor_msgs/msg/PointCloud2)@|\1[|" "$launch"

# RViz's config opens on Fixed Frame "map", and nothing here publishes a map frame - there
# is no SLAM and no Nav2. Every display then errors and the window stays empty, which reads
# as "RViz is broken" rather than "wrong frame". odom exists as soon as the controllers do.
rviz_cfg="$WS/src/unitree_go2_ros2/unitree_go2_sim/rviz/rviz.rviz"
sed -i -E "s|^([[:space:]]*)Fixed Frame: map$|\1Fixed Frame: odom|" "$rviz_cfg"

# lab.sdf is the hall the dog walks in, built from the upstream world with its sensors -
# they render again since the pod joined the render group (gid 110).
# headless.sdf, the same world without the sensor plugin, stays as a fallback: build the
# hall from it with `make_lab_world.py` and no argument if rendering ever breaks again.
python3 "$HERE/patches/make_headless_world.py"
python3 "$HERE/patches/make_lab_world.py" default

if [ "$1" != "--prebuilt" ]; then
  # --skip-keys: upstream asks for "unitree_applications", but the package is "unitree_application".
  cd "$WS"
  rosdep install --from-paths src --ignore-src -y --skip-keys unitree_applications
  colcon build --symlink-install
fi

echo
echo "Done. Start it with ./sim/start.sh, or the three terminals in docs/lab1-sim.md."
