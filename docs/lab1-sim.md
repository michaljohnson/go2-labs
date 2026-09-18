# Lab 1 — the Go2 in simulation (RAP cluster)

The dog walks in Gazebo and takes `/cmd_vel`. Your task is the node that publishes it.

The simulation itself comes from
[khaledgabr77/unitree_go2_ros2](https://github.com/khaledgabr77/unitree_go2_ros2); read its README
for what the packages do. This page only covers what is specific to our cluster.

## Once per pod

```bash
./sim/setup.sh
```

Clones the simulation at a pinned commit into `~/rap/cas/go2_ws`, applies the two patches below,
installs the dependencies and builds. The workspace lives in `~/rap`, the only storage that
survives a pod restart. The `apt` packages it installs do not survive, so run it again after a restart.

## Starting it — four terminals

Every terminal needs the same two exports first (`DISPLAY` only where a window opens):

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp   # without it, service calls hang - see the table below
cd ~/rap/cas/go2_ws && source install/setup.bash
```

```bash
# 1  simulation (leave running, give it ~1 min for the controllers)
ros2 launch unitree_go2_sim unitree_go2_launch.py rviz:=false \
  world:=$HOME/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_description/worlds/headless.sdf \
  disable_camera:=true disable_d455:=true disable_lidar_l1:=true disable_velodyne_lidar:=true

# 2  Gazebo window (view it in the browser through noVNC)
export DISPLAY=:0
gz sim -g

# 3  RViz — robot model, TF, later Nav2
export DISPLAY=:0
cd ~/rap/cas/go2_ws && source install/setup.bash
rviz2 -d ~/rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_sim/rviz/rviz.rviz

# 4  drive it: hold i / , to walk, j / l to turn, k to stop
cd ~/rap/cas/go2_ws && source install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

`export DISPLAY=:0` is needed in **every** terminal that opens a window, each time. To see it from
your own laptop instead of noVNC, see [`../viz/README.md`](../viz/README.md).

Checks: `ros2 control list_controllers` (both `active`), `ros2 topic echo /odom --once`
(`position.x` grows while walking), `ros2 topic hz /joint_states` (~150 Hz, one publisher).

## Why the patches, and the cluster's quirks

The pod is not a normal desktop, and four things follow from that. `setup.sh` handles the first two.

| Problem | Why | Our fix |
|---|---|---|
| Gazebo crashes at startup (`gz::gui::Application`, Qt) | the launch file hard-codes `gz_args` to `' -r'`, which starts the GUI client; the declared `gui` argument is unused | patch to `' -r -s'` (server only), window attached separately with `gz sim -g` |
| Server dies with `libEGL ... Permission denied` | the world loads `gz-sim-sensors-system`, which needs `/dev/dri`; the pod denies it | `worlds/headless.sdf`, a copy without that plugin, plus the `disable_*` launch arguments |
| Service calls hang, e.g. `controller_manager` is visible but never answers | `/dev/shm` is 64 MB in the pod; FastDDS moves data through shared memory | `sudo apt install ros-jazzy-rmw-cyclonedds-cpp` and `export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` in **all** terminals. Proper fix: a bigger `/dev/shm` in the pod spec |
| `rosdep` fails on `unitree_applications` | upstream typo — the folder is `unitree_application` | `--skip-keys unitree_applications` (in `setup.sh`) |

## Open

- **Lidar:** with the original world (no `world:=`) the `/velodyne_points/points` topics appear, but
  no data arrives. Needed for Nav2 — unresolved.
- **Nav2** as a student exercise only makes sense with a prepared package
  (`pointcloud_to_laserscan` + `slam_toolbox` + `nav2_bringup`), so students send goals and tune
  rather than assemble it.
- **A nicer world:** the ICCLab Summit XL house (`small_house_test.world`) is an Ignition world;
  a conversion to Harmonic naming exists but hasn't run yet.
