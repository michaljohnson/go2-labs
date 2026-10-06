# Everything a terminal in the pod needs. Source it, don't run it:
#
#   source ~/rap/cas/go2-labs/sim/env.sh
#
# Put this line in ~/.bashrc and you never type it again:
#
#   echo 'source ~/rap/cas/go2-labs/sim/env.sh' >> ~/.bashrc
#
# (~/.bashrc is wiped when the pod restarts, ~/rap is not - so the line has to be
# re-added after a restart, or baked into the image.)

source /opt/ros/jazzy/setup.bash
source "$HOME/rap/cas/go2_ws/install/setup.bash" 2>/dev/null

# No middleware is selected here any more. The simulation used rmw_zenoh because /dev/shm
# was 64 MB and the default middleware's service calls to controller_manager hung on it.
# /dev/shm has been 2 GB since 23 Sep 2026, so the reason is gone - and forcing a middleware
# had a cost of its own: any terminal that had not sourced this file saw no topics at all,
# which reads as "ROS is broken" rather than "wrong middleware".
#
# zenoh has not disappeared, it has moved to where it belongs: the router in rap-0 and a
# zenoh-bridge-ros2dds at each end carry /cmd_vel between the cluster and the dogs. That is
# a transport between sites, not a middleware for ROS nodes.
#
# To go back, for one terminal or by putting the line here again:
#   export RMW_IMPLEMENTATION=rmw_zenoh_cpp   # needs `ros2 run rmw_zenoh_cpp rmw_zenohd`

# Windows (Gazebo, RViz) draw on the pod's desktop, which you watch in the browser.
# An ssh session has no DISPLAY of its own; a terminal inside the desktop already has this.
export DISPLAY=:0
