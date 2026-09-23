# Driving a real dog from a RAP pod — the two paths

Both paths end in the same place: a node in the pod publishes `geometry_msgs/Twist` and the
dog walks. They differ only in how the command crosses from the cluster to the Jetson, and
that choice is the operator's — the student's node is identical either way.

| | Path A — ROS/DDS over a zenoh bridge | Path B — Unitree SDK |
|---|---|---|
| Pod middleware | `rmw_cyclonedds_cpp` | `rmw_zenoh_cpp` |
| On the Jetson | `cas-go2-robot` + `zenoh-bridge-ros2dds` | `cas-go2-sdk` |
| Containers on the Jetson | 3 — bridge, dog bridge, telemetry | 1 — all of it in one process |
| Reaches the cluster via | the `rap-0` zenoh router, `tcp/<router-address>:32447` | a zenoh router too; whether the `rap-0` one serves `rmw_zenoh` clients is untested |
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

Both ends dial **out** to a standalone zenoh router in the cluster. Neither the pod nor the
Jetson can accept an incoming connection - the pod has no external address, and the Jetson is
behind the lab NAT (it leaves as <lab-nat-address>) - so a router both can reach is the only place
they can meet. Verified 23 Sep 2026, with a dog walking.

| from | address |
|---|---|
| a pod, inside the cluster | `tcp/zenoh-router.rap-0.svc.cluster.local:7447` |
| a Jetson, from the lab wifi | `tcp/<router-address>:32447` |

```bash
# pod - bridge A, a client of the router, listening for nothing
cd ~/rap
ROS_DOMAIN_ID=5 ./zenoh-bridge-ros2dds client \
  -e tcp/zenoh-router.rap-0.svc.cluster.local:7447 --no-multicast-scouting
```

The router currently accepts unauthenticated sessions, so anything that can route to
<router-address> can publish `/cmd_vel` to a dog. Before students and four robots it should
want `usrpwd` credentials - the scripts already pass `ZENOH_USER`/`ZENOH_PASSWORD` through.

A `kubectl port-forward --address 0.0.0.0 7448:7448` on the teaching laptop works as a
stand-in when the router is unavailable, but then the laptop must stay awake for the whole
session and takes every dog down with it if it sleeps.

## Path A — ROS/DDS over a zenoh bridge

**Pod, terminal 1 — bridge A**
```bash
cd ~/rap
ROS_DOMAIN_ID=5 RUST_LOG=info ./zenoh-bridge-ros2dds client \
  -e tcp/zenoh-router.rap-0.svc.cluster.local:7447 --no-multicast-scouting
```
`client`, not the default `router` mode: it listens for nothing and dials out. Expect the
`v1.10.1` banner, then `New ROS 2 bridge detected` once a Jetson joins the same router.

**Jetson, terminal 1 — bridge B**
```bash
cd ~/go2-labs
ROUTER=tcp/<router-address>:32447 NAMESPACE=dog1 ./robot/run_bridge.sh
```
`run_bridge.sh` finds the dog-facing port by its 192.168.123.x address and pins CycloneDDS to
it. That pin is not a detail: DDS discovery is per-interface, so a bridge bound to the wifi
never sees the Humble container on the same host, on the same domain. The port is `enP8p1s0`
on the lab Jetsons and `enx...` on one with a USB adapter - detected, not typed.

Expect `allowance: Some(...)`, proof it read the allow list, then `New ROS 2 bridge detected`.

**Jetson, terminal 2 — the dog bridge**
```bash
cd ~/go2-labs && ./robot/run.sh
```
Ctrl+C here stops the dog, then the container.

**Jetson, terminal 3 — telemetry back** (see [Telemetry back from the dog](#telemetry-back-from-the-dog))
```bash
docker run --rm -it --network host --ipc host \
  -v ~/go2-labs/robot:/robot -e ROS_DOMAIN_ID=0 \
  cas-go2-robot /entrypoint.sh python3 /robot/go2_telemetry.py
```

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
UNTESTED: `rmw_zenoh` clients need a router, and the standalone one in `rap-0` speaks the
same protocol - so this path may be able to use it too, and skip the local router. Worth
trying before assuming each pod needs its own.

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

## Several dogs at once

`NAMESPACE=dog1` on `run_bridge.sh` passes the bridge's own `-n /dog1`. The bridge prepends
it to everything it routes, so the pod sees `/dog1/cmd_vel` while the robot side stays plain
`/cmd_vel` - nothing on the dog, in any container or in any node changes. Tested 23 Sep 2026.
Each Jetson gets its own, matching its hostname: `orin-nano-1` runs `NAMESPACE=dog1`.

The operator then addresses one dog:

```bash
ROS_NAMESPACE=dog1 ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

**This is addressing, not security.** Nothing stops anyone on that router publishing to
`/dog3/cmd_vel`. Enforcement belongs on the router: zenoh has access control built in
(`access_control` in its config, `default_permission: Deny`) and `usrpwd` authentication,
both currently off. A per-group user restricted to `dogN/**` is the only thing that actually
stops one group driving another's robot - a ROS namespace or domain never will, because the
bridge strips the DDS domain out of the key on the way through.

## Telemetry back from the dog

The dog's own topics never cross a bridge: `zenoh-bridge-ros2dds` routes what it finds
through `ros_discovery_info`, and the dog's firmware speaks DDS without running `rcl`, so it
announces no ROS nodes. Verified 23 Sep 2026 - only `/cmd_vel` crossed, `/lf/sportmodestate`
did not, however generous the allow list.

`robot/go2_telemetry.py` fixes that. It is a real ROS node, so what it publishes is
discovered and routed like anything else, and it translates on the way:

| the dog publishes | it republishes | type |
|---|---|---|
| `/utlidar/robot_odom` | `odom` | `nav_msgs/Odometry` - unchanged |
| `/lf/sportmodestate` | `mode` | `std_msgs/UInt8` - 0 idle, 1 balance stand, 5 lie, 7 damping |

Both are standard types, so the pod decodes them with nothing installed. Relative names, so
`ROS_NAMESPACE=dog1` gives `/dog1/odom` and `/dog1/mode`.

**Jetson, terminal 3**
```bash
docker run --rm -it --network host --ipc host \
  -v ~/go2-labs/robot:/robot -e ROS_DOMAIN_ID=0 \
  cas-go2-robot /entrypoint.sh python3 /robot/go2_telemetry.py
```

**Pod** - `ros2 topic echo /mode --once` before driving is the safety check `lab2-real.md`
asks for, and it now works from the operator's seat rather than only on the robot.

The SDK path has no equivalent yet: its bridge publishes nothing back, so the same
translation would have to be written into `go2_cmd_vel_sdk_bridge.py`.

## Known problem: the dog's clock

`/odom` carries a stamp from the dog, and on 23 Sep 2026 the dog's clock was ~38 minutes
behind the Jetson's. Record `/cmd_vel` (stamped in the pod) and `/odom` (stamped by the dog)
into one bag and the two traces sit 38 minutes apart - which looks like a student's bug and
is not. Either set the dog's clock, or restamp in `go2_telemetry.py` with the Jetson's, and
say in the lab text which clock the numbers come from.
