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

# The pod gives /dev/shm only 64 MB, which hangs the default middleware's service
# calls. zenoh ships in the image and doesn't use shared memory that way.
export RMW_IMPLEMENTATION=rmw_zenoh_cpp

# Windows (Gazebo, RViz) draw on the pod's desktop, which you watch in the browser.
# An ssh session has no DISPLAY of its own; a terminal inside the desktop already has this.
export DISPLAY=:0
