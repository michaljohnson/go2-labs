# Lab 1 — the Go2 in simulation (RAP cluster)

The dog walks in Gazebo and takes `/cmd_vel`. Your task is the node that publishes it.

The simulation itself comes from
[khaledgabr77/unitree_go2_ros2](https://github.com/khaledgabr77/unitree_go2_ros2); read its README
for what the packages do. This page only covers what is specific to our cluster.

## Getting in

Your pod has a desktop in the browser - nothing to install on your laptop:

```
https://rap-<group>.robopaas.dev/
```

Gazebo and RViz open as windows on that desktop, and a terminal there already has
everything set (see `sim/env.sh`). Work in that terminal, not over ssh: an ssh session has
no display, so any window you start from it dies with a Qt error.

## Once per pod

```bash
./sim/setup.sh
```

Clones the simulation at a pinned commit into `~/rap/cas/go2_ws`, applies the two patches below,
installs the dependencies and builds. The workspace lives in `~/rap`, the only storage that
survives a pod restart. The `apt` packages it installs do not survive, so run it again after a restart.

## Starting it

```bash
./sim/start.sh
```

That starts the zenoh router and Gazebo in the background (output in `~/rap/logs/`), waits
for the controllers, and leaves your terminal driving the dog: `i` / `,` walk, `j` / `l`
turn, `k` stop. The Gazebo window opens on the pod's desktop. `./sim/start.sh stop` ends it.

To see what it does, or to watch Gazebo's output while it runs, start the pieces yourself
in three terminals instead:

Every terminal needs ROS, the workspace, zenoh and `DISPLAY`. `sim/env.sh` sets all four:

```bash
source ~/rap/cas/go2-labs/sim/env.sh
```

Add it to `~/.bashrc` once and new terminals are ready by themselves:

```bash
echo 'source ~/rap/cas/go2-labs/sim/env.sh' >> ~/.bashrc
```

```bash
# 1  zenoh router - start it first, leave it running
ros2 run rmw_zenoh_cpp rmw_zenohd

# 2  simulation - the Gazebo window opens on the pod's desktop, watch it in the browser
ros2 launch unitree_go2_sim unitree_go2_launch.py rviz:=false \
  world:=$HOME/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_description/worlds/lab.sdf \
  disable_camera:=true disable_d455:=true disable_lidar_l1:=true disable_velodyne_lidar:=true

# 3  drive it: hold i / , to walk, j / l to turn, k to stop
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

`lab.sdf` is a hall with walls, a doorway and crates; `headless.sdf` is the bare plane.
RViz is optional: `rviz2 -d $HOME/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_sim/rviz/rviz.rviz`.

Checks: `ros2 control list_controllers` (both `active`), `ros2 topic hz /joint_states`
(~150 Hz, one publisher), `ros2 topic echo /odom/ground_truth --once` while walking.

## Why the patches, and the cluster's quirks

The pod is not a normal desktop. Two of these are still live; the other two are history worth
knowing, because the workarounds are still in the scripts.

| Problem | Why | Our fix |
|---|---|---|
| Gazebo crashes at startup (`gz::gui::Application`, Qt) | the window has nowhere to draw: an ssh session has no `DISPLAY`, because the container exports it only for the desktop it starts itself | `export DISPLAY=:0`, which `sim/env.sh` does. Then the launch opens its own window - no server-only patch needed |
| Server dies with `libEGL ... Permission denied` | **not a denial.** The GPU devices are there: `card0` is group `video` (44), which we have. Only the render nodes `renderD128/129` are group 110, which `ros` is not in - and only Mesa's GBM path wants those | render through a path that works: `DISPLAY=:0` (GLX, what the Summit XL sim uses here) or `--headless-rendering` (NVIDIA EGL device platform). `worlds/headless.sdf` and the `disable_*` flags remain as a fallback, not a requirement. Adding `supplementalGroups: [110]` to the pod would open the third path too |
| Service calls hang, e.g. `controller_manager` is visible but never answers | **fixed in the pod.** `/dev/shm` used to be 64 MB, too small for FastDDS's shared-memory transport; it is 2 GB now | nothing to do - the default middleware works. `sim/env.sh` still selects zenoh, which costs nothing (same real-time factor) and is the middleware the real-robot labs use. Drop that line from `env.sh` if you prefer the default |
| `rosdep` fails on `unitree_applications` | upstream typo — the folder is `unitree_application` | `--skip-keys unitree_applications` (in `setup.sh`) |

## Open

- **Lidar:** with the original world (no `world:=`) the `/velodyne_points/points` topics appear, but
  no data arrives. Needed for Nav2 — unresolved.
- **Nav2** as a student exercise only makes sense with a prepared package
  (`pointcloud_to_laserscan` + `slam_toolbox` + `nav2_bringup`), so students send goals and tune
  rather than assemble it.
- **A nicer world:** the ICCLab Summit XL house (`small_house_test.world`) is an Ignition world;
  a conversion to Harmonic naming exists but hasn't run yet.
