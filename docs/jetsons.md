# The dogs — who is who

One Jetson per dog. The hostname number is the dog number: `orin-nano-1` drives `dog1` and
answers on `/dog1/cmd_vel`. Keeping those the same removes the one mistake nobody catches
until a robot moves that shouldn't have.

`orin-nano-1`, `-2`, `-3` and `-5` exist; `orin-nano-4` is expected and will drive `dog4`.
The gap is harmless - what matters is that a machine's number and its dog's number agree,
not that they run consecutively.

They all sit on the **PhysicalAI** wifi (192.168.0.0/24) and answer to `orin-nano-N.local`,
so use the names, not the addresses — a reboot can change the DHCP lease.

| Dog | Jetson          | Wifi          | Dog port                    | Images              | Driven a dog |
| --- | --------------- | ------------- | --------------------------- | ------------------- | ------------ |
| 1   | `orin-nano-1` | 192.168.0.217 | `enP8p1s0` 192.168.123.99 | robot + sdk + zenoh | yes          |
| 2   | `orin-nano-2` | 192.168.0.145 | `enP8p1s0` 192.168.123.99 | robot + sdk + zenoh | yes          |
| 3   | `orin-nano-3` | 192.168.0.191 | `enP8p1s0` 192.168.123.99 | robot + sdk + zenoh | yes          |
| 5   | `orin-nano-5` | 192.168.0.58  | `enP8p1s0` 192.168.123.99 | robot + sdk + zenoh | yes          |

`192.168.123.99` repeats on every Jetson on purpose: each is alone on its own dog's cable,
so the addresses never meet. The dog itself is never reconfigured - it stays on its factory
setup, and `ROS_DOMAIN_ID` on the robot is irrelevant, because nothing on the dog speaks ROS.

Which dog a Jetson is belongs to the machine, not to whoever remembers to type it:

```bash
echo 'NAMESPACE=dog1' | sudo tee /etc/default/go2-dog
```

The start scripts read it and pass `-r __ns:=/dog1`, so every command below is identical on
every machine.

## The route to the cluster

Both ends dial **out** to a standalone zenoh router. Neither can accept a connection: the pod
has no external address, and the Jetsons are behind the lab NAT (they leave as `<lab-nat-address>`).

| from     | address                                           |
| -------- | ------------------------------------------------- |
| a pod    | `tcp/zenoh-router.rap-0.svc.cluster.local:7447` |
| a Jetson | `tcp/<router-address>:32447`                      |

The router takes unauthenticated sessions today, so anything that can route to that NodePort
can drive a dog. Before students and four robots it should want `usrpwd`.

## Per Jetson, once (already done - just for information)

```bash
# Swiss keyboard - localectl refuses on Ubuntu, console-setup owns this file
sudo cp /etc/default/keyboard /etc/default/keyboard.bak
sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="ch"/; s/^XKBVARIANT=.*/XKBVARIANT=""/' /etc/default/keyboard
sudo systemctl restart console-setup

# wifi power save costs more than the network does: on orin-nano-2 it took the ping from the
# laptop from 43 ms average and 27 ms jitter down to 9 ms and 2.8 ms. The radio sleeps between
# beacons, and the jitter is what teleop feels.
sudo nmcli con modify PhysicalAI 802-11-wireless.powersave 2   # applies on reconnect
nmcli -g 802-11-wireless.powersave con show PhysicalAI        # must say 'disable'
sudo iw dev wlP1p1s0 set power_save off             # and now, without reconnecting

# fixed address on the dog's network - the Go2 runs no DHCP server
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.123.99/24
sudo nmcli con up "Wired connection 1"
ping -c2 192.168.123.161            # the dog's main board
```

Images - stream them straight from a Jetson that already has them, so nothing is written to
disk on either machine:

```bash
ssh ema-student@orin-nano-1.local 'docker save cas-go2-robot:latest | gzip -1' | docker load
ssh ema-student@orin-nano-1.local 'docker save cas-go2-sdk:latest   | gzip -1' | docker load
docker pull eclipse/zenoh-bridge-ros2dds:1.10.1
```

Check the IDs afterwards against the machine you streamed from - same bytes, never rebuilt:

```bash
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E "cas-go2|zenoh"
```

The repo goes over by `scp` from the laptop rather than `git clone`: it is private on
github.zhaw.ch, and four machines students sit at is the wrong place for ZHAW credentials.

```bash
scp -r ~/cas/go2 ema-student@orin-nano-N.local:~/go2-labs
```

## Starting a dog

Dog standing, remote in your hand, 2-3 m clear. One command, three windows in tmux:

```bash
cd ~/go2-labs
ROUTER=tcp/<router-address>:32447 ./robot/start.sh
tmux attach -t dog          # Ctrl-b then 0/1/2 to switch, Ctrl-b then d to detach
```

That starts the zenoh bridge, the `/cmd_vel` bridge and the telemetry node. tmux rather than
three ssh terminals because a closed terminal used to take a dog off the air silently - the
topics stay visible in the pod either way, so it looks exactly like a working robot until you
publish into it.

And in the pod:

```bash
source ~/rap/cas/go2-labs/sim/env.sh
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp     # after env.sh, which sets zenoh
export ROS_DOMAIN_ID=5
ros2 topic list --no-daemon                      # /dog1/cmd_vel, /dog1/odom, /dog1/mode
ros2 topic echo /dog1/mode --once                # a live number means a real robot
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r __ns:=/dog1
```

## Stopping, and shutting a Jetson down

How you stop things decides what is left behind. The whole sequence:

```bash
# 1. the dog first - SIGINT, so the node's finally: block sends StopMove.
#    docker stop sends SIGTERM, which Python does not turn into KeyboardInterrupt, and the
#    dog would keep walking at its last commanded velocity.
docker kill -s INT go2 2>/dev/null; sleep 2

# 2. the rest gracefully, so their zenoh sessions close. docker rm -f is SIGKILL: the
#    session never closes, its keys stay declared in the router, and the pod is left with
#    topics that have a publisher and no robot behind them.
docker stop zbridge go2-telemetry 2>/dev/null

# 3. anything left, named or not - a stray container still answering on /cmd_vel is a dog
#    that obeys commands addressed to nobody
docker ps -aq --filter ancestor=cas-go2-robot \
              --filter ancestor=cas-go2-sdk \
              --filter ancestor=eclipse/zenoh-bridge-ros2dds | xargs -r docker rm -f
tmux kill-session -t dog 2>/dev/null
docker ps                      # expect nothing

# 4. then power
sudo shutdown -h now
```

Wait until it stops answering - `ping orin-nano-N.local` from the laptop - before cutting
power. The root filesystem is on eMMC and a hard cut during a write means a reflash, which
would take the images with it.

**If the Jetson is powered from the dog rather than its own supply, shut the Jetson down
before switching the robot off.** Turning the dog off is then a power cut on a live machine.

The Ethernet cable is different: unplug it whenever you like, no shutdown needed. Only power
needs the clean stop. But see the next paragraph, because the cable has its own trap.

**After swapping a dog, power-cycling one, or moving its cable, restart that dog's
containers.** CycloneDDS binds to the interface at startup and never recovers when the link
flaps. The container stays up and looks perfectly healthy while reaching nothing -
`ddsi_udp_conn_write to udp/239.255.0.1:7400 failed with retcode -1` in its log is the only
sign. This cost an evening on 23 Sep 2026.

`IFACE` is found from the `192.168.123.x` address, so the commands are identical on every one.
The full chain, and the SDK alternative, are in [`driving-a-dog.md`](driving-a-dog.md).
