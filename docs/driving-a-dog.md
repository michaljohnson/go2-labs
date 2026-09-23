# Driving a real dog from a RAP pod — the two paths

Both paths end in the same place: a node in the pod publishes `geometry_msgs/Twist` and the
dog walks. They differ only in how the command crosses from the cluster to the Jetson, and
that choice is the operator's — the student's node is identical either way.

| | Path A — ROS/DDS over a zenoh bridge | Path B — Unitree SDK |
|---|---|---|
| Pod middleware | `rmw_cyclonedds_cpp` | `rmw_zenoh_cpp` |
| On the Jetson | `cas-go2-robot` + `zenoh-bridge-ros2dds` | `cas-go2-sdk` |
| Processes on the Jetson | 2 | 1 |
| Port into the pod | 7448 | 7447 |
| Needs installing in the pod | `ros-jazzy-rmw-cyclonedds-cpp`, after every restart | nothing |
| Proven on a real dog | 23 Sep 2026 | 22 Sep 2026 |

**Never run both against the same dog.** Two bridges both sending `Move` to one robot is the
one failure mode that can hurt it.

## Before either path

```bash
# Jetson, once per boot - the radio's power save costs ~35 ms of latency and 25 ms of jitter
sudo iw dev wlP1p1s0 set power_save off

# the dog: standing, sport mode, remote in your hand, 2-3 m clear
```

The Jetsons reach the pod through a **NodePort on the port that path uses**. Until that
Service exists, the stand-in is a port-forward on the teaching laptop, which means the laptop
must stay awake for the whole session and takes every dog down with it if it sleeps:

```bash
# laptop - temporary stand-in for the NodePort
kubectl -n rap-9 port-forward <pod> --address 0.0.0.0 7448:7448    # path A
kubectl -n rap-9 port-forward <pod> --address 0.0.0.0 7447:7447    # path B
```

`<router>` below means the NodePort address (`robopaas.dev:<nodePort>`) or, with the
stand-in, the laptop's address on the lab wifi — `192.168.0.135`.

## Path A — ROS/DDS over a zenoh bridge

**Pod, terminal 1 — bridge A**
```bash
cd ~/rap
ROS_DOMAIN_ID=5 RUST_LOG=info ./zenoh-bridge-ros2dds -l tcp/0.0.0.0:7448 --no-multicast-scouting
```
Expect the `v1.10.1` banner. Nothing else until a peer connects.

**Jetson, terminal 1 — bridge B**
```bash
docker rm -f zbridge
docker run --rm -it --network host --name zbridge \
  -e ROS_DOMAIN_ID=0 -e ROS_DISTRO=humble \
  -e CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces><NetworkInterface name="enP8p1s0" priority="default" multicast="default"/></Interfaces></General></Domain></CycloneDDS>' \
  -v ~/go2-labs/robot/bridge_dog.json5:/c.json5 \
  eclipse/zenoh-bridge-ros2dds:1.10.1 \
  client -c /c.json5 -e tcp/<router>:7448 --no-multicast-scouting
```
Expect `allowance: Some(...)` — proof it read the config — and `New ROS 2 bridge detected`.
`CYCLONEDDS_URI` pins the bridge to the same port the dog is on; without it the bridge picks
the wifi instead and never sees the Humble container, on the same host, on the same domain.

**Jetson, terminal 2 — the dog bridge**
```bash
cd ~/go2-labs && ./robot/run.sh
```
Ctrl+C here stops the dog, then the container.

**Pod, terminal 2 — check before driving**
```bash
source ~/rap/cas/go2-labs/sim/env.sh
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp     # after env.sh, which sets zenoh
export ROS_DOMAIN_ID=5
echo "$RMW_IMPLEMENTATION / $ROS_DOMAIN_ID"      # never trust it, check it
ros2 topic list --no-daemon                      # expect /cmd_vel
```
`--no-daemon` matters: the ROS 2 CLI daemon caches discovery per domain and will happily
show you a list from ten minutes and one middleware ago.

**Pod, terminal 3 — teleop**
```bash
source ~/rap/cas/go2-labs/sim/env.sh
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=5
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```
Hold `i` to walk, `k` stops at once.

## Path B — Unitree SDK

**Pod, terminal 1 — the zenoh router**
```bash
source ~/rap/cas/go2-labs/sim/env.sh
ros2 run rmw_zenoh_cpp rmw_zenohd
```

**Jetson, terminal 1 — the SDK bridge, dry first**
```bash
cd ~/go2-labs
NAMESPACE=dog1 ROUTER=tcp/<router>:7447 ./robot/run_sdk.sh --dry-run
```
It logs every `Move` it would send and the dog does not move. Swap `--dry-run` for `run`
when the log looks right.

**Pod, terminal 2 — teleop**
```bash
source ~/rap/cas/go2-labs/sim/env.sh              # rmw_zenoh, which this path wants
export ROS_DOMAIN_ID=5
export ROS_NAMESPACE=dog1
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

## Stopping

`k` in teleop is the fast stop - the dog gets an explicit stop command. Ctrl+C in the bridge
is the hard stop: it sends `StopMove` and exits. Both work; `k` is the one to teach.

## What neither path gives you yet

The dog's own telemetry does not reach the pod. `zenoh-plugin-ros2dds` bridges what it finds
through `ros_discovery_info`, and the dog's firmware speaks DDS without running `rcl`, so it
announces no ROS nodes - verified on 23 Sep 2026, when only `/cmd_vel` crossed and
`/lf/sportmodestate` did not. Getting `/sportmodestate` or odometry into the pod needs a
small node on the Jetson that subscribes to the dog and republishes as a real ROS node.
Path B needs the same thing, written into the SDK bridge instead.
