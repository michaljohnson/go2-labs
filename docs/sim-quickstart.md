# Starting the simulation yourself

Four terminals in your pod's desktop. Every one of them starts with the same line, because a
fresh terminal has nothing loaded - `~/.bashrc` does not survive a pod restart.

```bash
source ~/rap/cas/go2-labs/sim/env.sh
```

That sets ROS, the simulation workspace, `RMW_IMPLEMENTATION` and `DISPLAY=:0`. Without it
`ros2` is not even on the path.

`./sim/start.sh` does all of the below in one command and is what to use when you just want
the simulation running. Use this page when you want to see the pieces, or when something is
wrong and you need to watch each one come up.

## 1. The zenoh router — first, and on its own

```bash
source ~/rap/cas/go2-labs/sim/env.sh
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Nodes that start before the router do not find each other, and the failure looks like Gazebo
being broken: the controllers report `Unable to connect to a Zenoh router` and the simulation
dies. Start this one and leave it.

## 2. Gazebo and the dog

```bash
source ~/rap/cas/go2-labs/sim/env.sh
ros2 launch unitree_go2_sim unitree_go2_launch.py rviz:=false \
  world:=$HOME/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_description/worlds/lab.sdf
```

Give it about forty seconds: Gazebo has to start, and the controllers have to be loaded and
activated before the dog reacts to anything. The window opens on the pod's desktop - the one
you are watching in the browser - not in this terminal.

## 3. Drive it

```bash
source ~/rap/cas/go2-labs/sim/env.sh
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

`i` walks, `,` reverses, `j` and `l` turn, `k` stops. Hold the key: it publishes on key
presses, not continuously.

This is the whole point of the lab - your own node publishes the same `geometry_msgs/Twist`
on `/cmd_vel`, and the simulated dog cannot tell the difference. Nor can the real one.

## 4. RViz, if you want it

```bash
source ~/rap/cas/go2-labs/sim/env.sh
rviz2 -d $HOME/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_sim/rviz/rviz.rviz
```

Optional, and not free: it costs about half a CPU core and half a gigabyte, and the pod has
no GPU path for it, so it renders on the CPU and looks rough over the browser desktop. If the
simulation feels slow, close RViz first.

## Checking rather than guessing

```bash
ros2 topic list                    # what exists
ros2 topic hz /joint_states        # about 150 Hz when the dog is alive
ros2 topic echo /odom --once       # where it thinks it is
```

`ros2 topic list` asks a background daemon that caches its answers. After changing
`ROS_DOMAIN_ID` or `RMW_IMPLEMENTATION`, add `--no-daemon` or it will cheerfully tell you
what was true ten minutes ago.

## Stopping

`Ctrl+C` each terminal, router last. Or:

```bash
pkill -f unitree_go2_launch; pkill -f "gz sim"; pkill -f rmw_zenohd
```
