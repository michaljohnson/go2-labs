# The four dogs — who is who

Four Jetsons, `orin-nano-1` … `orin-nano-4`, one per dog. The hostname is the namespace:
`orin-nano-1` drives `dog1` and answers on `/dog1/cmd_vel`. Keeping those the same removes
the one mistake nobody catches until a robot moves that shouldn't have.

All four sit on the **PhysicalAI** wifi (192.168.0.0/24) and answer to `orin-nano-N.local`,
so use the names, not the addresses — a reboot can change the DHCP lease.

| Dog | Jetson | Wifi | Dog port | Images | Bridge | Real dog |
|---|---|---|---|---|---|---|
| 1 | `orin-nano-1` | 192.168.0.217 | `enP8p1s0` 192.168.123.99 | robot + zenoh | yes | **23 Sep 2026** |
| 2 | `orin-nano-2` | 192.168.0.145 | `enP8p1s0` 192.168.123.99 | robot + sdk + zenoh | yes | **22 & 23 Sep 2026** |
| 3 | `orin-nano-3` | ? | ? | — | — | — |
| 4 | `orin-nano-4` | ? | ? | — | — | — |

`192.168.123.99` repeats on every Jetson on purpose: each is alone on its own dog's cable,
so the addresses never meet. The dog itself is never reconfigured - it stays on its factory
setup, and `ROS_DOMAIN_ID` on the robot is irrelevant, because nothing on the dog speaks ROS.

## The route to the cluster

Both ends dial **out** to a standalone zenoh router. Neither can accept a connection: the pod
has no external address, and the Jetsons are behind the lab NAT (they leave as `<lab-nat-address>`).

| from | address |
|---|---|
| a pod | `tcp/zenoh-router.rap-0.svc.cluster.local:7447` |
| a Jetson | `tcp/<router-address>:32447` |

The router takes unauthenticated sessions today, so anything that can route to that NodePort
can drive a dog. Before students and four robots it should want `usrpwd`.

## Per Jetson, once

```bash
# Swiss keyboard - localectl refuses on Ubuntu, console-setup owns this file
sudo cp /etc/default/keyboard /etc/default/keyboard.bak
sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="ch"/; s/^XKBVARIANT=.*/XKBVARIANT=""/' /etc/default/keyboard
sudo systemctl restart console-setup

# wifi power save costs more than the network does: on orin-nano-2 it took the ping from the
# laptop from 43 ms average and 27 ms jitter down to 9 ms and 2.8 ms. The radio sleeps between
# beacons, and the jitter is what teleop feels.
sudo nmcli con modify PhysicalAI wifi.powersave 2   # 2 = disabled, applies on reconnect
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
docker pull eclipse/zenoh-bridge-ros2dds:1.10.1
```

The repo goes over by `scp` from the laptop rather than `git clone`: it is private on
github.zhaw.ch, and four machines students sit at is the wrong place for ZHAW credentials.

```bash
scp -r ~/cas/go2 ema-student@orin-nano-N.local:~/go2-labs
```

## Starting a dog

Three terminals on the Jetson. Dog standing, remote in your hand, 2-3 m clear.

```bash
cd ~/go2-labs
ROUTER=tcp/<router-address>:32447 NAMESPACE=dog1 ./robot/run_bridge.sh   # the link
./robot/run.sh                                                         # /cmd_vel -> the dog
docker run --rm -it --network host --ipc host \
  -v ~/go2-labs/robot:/robot -e ROS_DOMAIN_ID=0 \
  cas-go2-robot /entrypoint.sh python3 /robot/go2_telemetry.py         # /odom and /mode back
```

And in the pod:

```bash
source ~/rap/cas/go2-labs/sim/env.sh
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp     # after env.sh, which sets zenoh
export ROS_DOMAIN_ID=5
ros2 topic echo /mode --once                     # 1 = balance stand, it will accept Move
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

`IFACE` is found from the `192.168.123.x` address, so the commands are identical on all four.
The full chain, and the SDK alternative, are in [`driving-a-dog.md`](driving-a-dog.md).
