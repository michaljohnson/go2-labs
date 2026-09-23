# Driving a real dog from a RAP pod — the two paths

Both paths end in the same place: a node in the pod publishes `geometry_msgs/Twist` and the
dog walks. They differ only in how the command crosses from the cluster to the Jetson, and
that choice is the operator's — the student's node is identical either way.

| | Path A — ROS/DDS over a zenoh bridge | Path B — Unitree SDK |
|---|---|---|
| Pod middleware | `rmw_cyclonedds_cpp` | `rmw_zenoh_cpp` |
| On the Jetson | `cas-go2-robot` + `zenoh-bridge-ros2dds` | `cas-go2-sdk` |
| Containers on the Jetson | 3 — bridge, dog bridge, telemetry | 1 — all of it in one process |
| Reaches the cluster via | the `rap-0` zenoh router, `tcp/<router-address>:32447` | the same router - `rmw_zenoh` clients connect to it directly, so no local `rmw_zenohd` |
| Needs installing in the pod | `ros-jazzy-rmw-cyclonedds-cpp`, after every restart | nothing |

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
they can meet

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

A `kubectl port-forward --address 0.0.0.0 7448:7448` on the teaching laptop works as a
stand-in if the router is ever unavailable, with bridge A listening rather than dialling out.
Avoid it: the laptop then has to stay awake for the whole session and takes every dog down
with it if it sleeps. Four dogs have run through the router without it.

## Path A — ROS/DDS over a zenoh bridge

The Jetson side is one command, which is what you want with four of them:

```bash
cd ~/go2-labs
ROUTER=tcp/<router-address>:32447 ./robot/start.sh      # bridge, dog bridge, telemetry
tmux attach -t dog                                     # Ctrl-b 0/1/2, Ctrl-b d to detach
./robot/start.sh stop                                  # ends the session and the containers
```

tmux rather than three ssh terminals because a closed terminal used to take a dog off the
air silently - the topics stay visible in the pod either way, so it looks exactly like a
working robot until you publish into it.

The rest of this section is the same three pieces started by hand, which is what you want
when something is wrong and you need to see each one come up.

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
ROUTER=tcp/<router-address>:32447 ./robot/run_bridge.sh
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
cd ~/go2-labs && ./robot/run.sh telemetry
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

One container instead of three: `cas-go2-sdk` speaks `rmw_zenoh` to the router and the Unitree
SDK to the dog, in one process. No zenoh bridge, no `cas-go2-robot`.

**Pod — point `rmw_zenoh` at the router.** There is no local `rmw_zenohd` on this path; the
same `rap-0` router serves both designs, and the two use different key layouts so they do not
see each other.

```bash
cat > $HOME/rap/zenoh_session.json5 <<'EOF'
{
  mode: "client",
  connect: { endpoints: ["tcp/zenoh-router.rap-0.svc.cluster.local:7447"] },
  transport: { shared_memory: { enabled: false } },
}
EOF

source ~/rap/cas/go2-labs/sim/env.sh          # keeps rmw_zenoh_cpp
export ZENOH_SESSION_CONFIG_URI=$HOME/rap/zenoh_session.json5
export ROS_DOMAIN_ID=5
```

`shared_memory: false` is not optional. Without it `rcl` fails to initialise with
`Failed to create POSIX SHM provider` and `OS error 12`, even with 2 GB free on `/dev/shm`.
It is a same-host optimisation and both ends here talk over TCP.

**Jetson — dry first, nothing reaches the dog**

```bash
cd ~/go2-labs
ROUTER=tcp/<router-address>:32447 ./robot/run_sdk.sh --dry-run
```

It logs every `Move` it would send. Swap `--dry-run` for `run` when the log looks right.
The namespace comes from `/etc/default/go2-dog`, same as Path A.

**Pod — drive**

```bash
ROS_NAMESPACE=dog1 ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

Remember to `unset ZENOH_SESSION_CONFIG_URI` in any terminal you later use for Path A - it
lingers in the shell and sends you to the wrong middleware.

## Stopping

`k` in teleop is the fast stop - the dog gets an explicit stop command. A zero Twist does the
same from a script. Ctrl+C in the bridge is the hard stop: it sends `StopMove` and exits.
`k` is the one to teach.

All three depend on the bridge being alive. **Silence is not a stop** - sport mode keeps the
last velocity until told otherwise, so a container that dies mid-walk leaves the dog going
until the remote intervenes. That happened on 23 Sep 2026 with two dogs.

Shutting a Jetson down has its own order, in [`jetsons.md`](jetsons.md#stopping-and-shutting-a-jetson-down):
SIGINT the dog bridge first so it sends `StopMove`, `docker stop` the rest so their zenoh
sessions close, then power.

## Several dogs at once

Each dog's identity is a ROS namespace, applied as a remap on the nodes that run on its
Jetson. It belongs to the machine, so nobody types it again:

```bash
echo 'NAMESPACE=dog1' | sudo tee /etc/default/go2-dog
```

`run.sh` and `run_sdk.sh` read that file and pass `-r __ns:=/dog1`, which prefixes every
relative name the node uses - `/dog1/cmd_vel`, `/dog1/odom`, `/dog1/mode`. The dog's own
topics stay absolute and untouched, which is what you want: `/api/sport/request` and
`/utlidar/robot_odom` belong to the robot, not to us.

`-r __ns:=` is the documented ROS 2 mechanism and it is what these scripts use. An earlier
version passed `ROS_NAMESPACE` instead and never produced a namespaced topic - the option had
looked like it worked since the day it was written, because with one dog `/cmd_vel` is right
either way. If you see a node on plain `/cmd_vel` when you expected `/dogN/`, that is the
shape of the bug: check the node's own log line, which shows its namespace.

The operator then addresses one dog:

```bash
ROS_NAMESPACE=dog1 ros2 run teleop_twist_keyboard teleop_twist_keyboard   # works here: the
                                                                          # CLI honours it
ros2 topic pub -r 10 /dog1/cmd_vel geometry_msgs/msg/Twist "{angular: {z: 0.4}}"
```

The zenoh bridge also has its own `-n /dog1`, which scopes everything it routes without any
node knowing. It works, and it is one flag instead of two. It is not used here because the
SDK path has no bridge, and one mechanism for both paths beats two. **Never set both** - a
bridge scoping already-namespaced topics gives you `/dog1/dog1/cmd_vel`.

**This is addressing, not security.** Nothing stops anyone on that router publishing to
`/dog3/cmd_vel`. Enforcement would have to live in the router: zenoh has access control and
`usrpwd` authentication built in, both off. A ROS namespace or a DDS domain never will - the
bridge strips the domain out of the key on the way through.

## Trusting what you see

A topic in `ros2 topic list` does not mean a robot is behind it. Four ways it can lie:

- **Ghost publishers.** A container killed with `docker rm -f` never closes its zenoh session,
  so its keys stay declared and the pod's bridge keeps offering topics for them.
  `ros2 topic info /odom --no-daemon -v` shows the publisher as `zenoh_bridge_ros2dds` with
  `Topic type hash: INVALID` - that is a ghost. Use `docker stop` before `docker rm`.
  They accumulate: on 23 Sep 2026 the pod listed three dogs while two of the machines were
  switched off. **Restarting bridge A clears them** - the stale keys are held there, not in
  the router, so this needs nobody's help. Worth doing before a class, so the topic list
  means something.
- **A stale CLI daemon.** `ros2 topic list` asks a background daemon that caches per domain,
  so after changing `ROS_DOMAIN_ID` or `RMW_IMPLEMENTATION` it will happily answer from
  minutes ago. Always `--no-daemon`.
- **A dog in the wrong mode.** The topics are all there and the dog ignores every command.
  Check `/dogN/mode`.
- **A container that is alive and deaf.** CycloneDDS binds to the dog-facing interface at
  startup and does not recover if that link flaps - which it does whenever a dog is swapped
  or power-cycled. The container stays up, `docker ps` looks healthy, the topics still exist
  in the pod, and nothing reaches the robot. The only symptom is in its log:
  `ddsi_udp_conn_write to udp/239.255.0.1:7400 failed with retcode -1`, repeating.
  **Restart a dog's containers after swapping or power-cycling the robot.** Diagnose it by
  echoing `/api/sport/request` on the Jetson: commands in and nothing out means this.

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
cd ~/go2-labs && ./robot/run.sh telemetry
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
