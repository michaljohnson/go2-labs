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


# To go back, for one terminal or by putting the line here again:
#   export RMW_IMPLEMENTATION=rmw_zenoh_cpp   # needs `ros2 run rmw_zenoh_cpp rmw_zenohd`

# Windows (Gazebo, RViz) draw on the pod's desktop, which you watch in the browser.
# An ssh session has no DISPLAY of its own; a terminal inside the desktop already has this.
export DISPLAY=:0
