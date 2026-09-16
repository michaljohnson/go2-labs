# Lab 2 — the real Go2

Same interface as lab 1: your node publishes `/cmd_vel`. The difference is the bridge, because the
dog doesn't understand `/cmd_vel` — walking is a `Move` request on `/api/sport/request`
(`../robot/go2_cmd_vel_bridge.py`).

The Jetson on the dog is cabled to the dog's internal network (`192.168.123.x`, main board at
`.161`) and joins a Wi-Fi for SSH. Because the dog speaks CycloneDDS, ROS 2 sees its topics
directly — `/sportmodestate`, `/lowstate`, `/utlidar/cloud`, `/wirelesscontroller`.

Everything runs in a container, so nothing is installed on the Jetson and its Ubuntu version
doesn't matter.

## Safety, before anything moves

- The dog **stands** in sport mode. Lying down or in damping it ignores `Move`.
  Check: `ros2 topic echo /sportmodestate --once | grep -E '^mode'` (1 = balance stand, 5 = lie down, 7 = damping)
- **Remote control in your hand.** L2+B = damping, the dog lies down softly. The phone app must not
  be steering at the same time
- 2–3 m clear around the dog
- The bridge caps speed at 0.3 m/s forward, 0.2 m/s sideways, 0.6 rad/s turning
  (raise with `--ros-args -p max_vx:=0.5`)
- **Hold** the key to walk. `teleop_twist_keyboard` only publishes on key presses, so the bridge
  repeats the last command at 10 Hz and sends `StopMove` 1 s after the last one. `k` stops at once;
  Ctrl+C in the bridge stops the dog before it exits

## Driving it 🚧

🚧 = the image has not been built and driven on the dog yet; the native path in the appendix has.

```bash
ssh <user>@<jetson>
git clone https://github.zhaw.ch/cas-physical-ai/go2-labs.git
cd go2-labs
docker build -t cas-go2-robot robot/      # once, ~10 min

./robot/run.sh          # terminal 1: the bridge (Ctrl+C stops the dog, then the container)
./robot/teleop.sh       # terminal 2: the keyboard — hold i / , / j / l, k stops
```

`robot/entrypoint.sh` finds the port to the dog itself: the one with a `192.168.123.x` address.
`./robot/run.sh bash` gives a shell in the container with ROS and the Unitree messages loaded, e.g.
for `ros2 topic list`.

## Task — record and replay a route

A bag records messages and plays them back. Nothing in the chain can tell whether `/cmd_vel` comes
from the keyboard, from a bag, or from your own node — the dog walks either way.

**Bronze — record and replay**

1. Start the bridge and teleop as above, and drive a short route: a few metres, one turn.
2. Record while you drive, in a third terminal:
   ```bash
   ros2 bag record -o my_route /cmd_vel /odom /sportmodestate
   ```
   Only these three topics. With the lidar the bag grows to gigabytes.
3. Stop the recording and teleop, leave the bridge running, then:
   ```bash
   ros2 bag play my_route
   ```
4. The dog walks the route again. Watch what the bridge prints while it does.

**Silver — compare**

5. Mark where the dog ends up, driven and replayed.
6. From the bag, plot the commanded speed (`/cmd_vel`) against the measured one (`/odom`),
   e.g. in Lichtblick (see [`../viz/README.md`](../viz/README.md)).
7. **For the report:** why does the dog not end up in the same place? What would it take for it to?

**Gold — simulation ↔ reality**

8. Record the same route in the simulation (lab 1), replay it on the real dog, and the other way round.
9. **For the report:** where do the differences come from — the controller, the ground, timing?

**Safety on replay:** the dog moves with nobody holding a key. Remote in hand, clear space. When the
bag ends, the bridge sends `StopMove` a second later; `Ctrl+C` on the playback stops it the same way.

**Bags between ROS versions:** the simulation (Jazzy) writes `.mcap` by default, the container runs
Humble. For step 8, either record with `--storage sqlite3`, or install
`ros-humble-rosbag2-storage-mcap` in the container.

## Troubleshooting

**Teleop runs, the dog doesn't move.** In order:
1. Does the bridge print `stop` about 1 s after you tap `i`? If not, the keyboard isn't reaching it
2. `ros2 node info /go2_cmd_vel_bridge | grep -A3 Publishers` must list `/api/sport/request`, not `/dryrun`
3. Is the dog standing? See `mode` above
4. `ros2 topic echo /api/sport/response` while you press `i` — the dog's reply says why it refuses

**`ros2 topic list` stays empty** — the container isn't reaching the dog's network. Check
`ping 192.168.123.161` on the Jetson, and that `run.sh` is using `--network host`. Discovery can
take a few seconds the first time.

**No SSH to the Jetson** — it needs about a minute after power-on. Its Wi-Fi address can change;
find it by comparing SSH host keys:
`ssh-keyscan -t ed25519 <ip> 2>/dev/null | ssh-keygen -lf -`

**Switching the Jetson's Wi-Fi** — only over a cable or a second link, never over the Wi-Fi you are
changing. At boot NetworkManager picks the visible network with the highest
`connection.autoconnect-priority`; **never leave every reachable network at autoconnect `no`**, or
the Jetson comes up with no Wi-Fi and only a cable gets you back in.

## Appendix — native install (for testing, not for students) ✅

What was set up on the lab Jetson before the image existed, and what the bridge was tested with.
Follow the [unitree_ros2 README](https://github.com/unitreerobotics/unitree_ros2) — it is written
for Foxy, so read `humble` wherever it says `foxy`, and its "compile cyclonedds" step is skipped on
Humble. Three things are specific to this robot:

- **ROS 2 Humble**, because that Jetson runs Ubuntu 22.04. `ros-base` is enough; it has no screen
- **In `~/unitree_ros2/setup.sh`:** the network interface is the port that leads to the dog,
  `enP8p1s0` on that Jetson — the one with a `192.168.123.x` address in `ip -br addr`. The README's
  "set 192.168.123.99" step is unnecessary, that address already exists
- **Source `setup.sh` per terminal, not in `~/.bashrc`.** The Jetson is shared, and other setups on
  it use their own CycloneDDS

Then, in two terminals:

```bash
python3 go2_cmd_vel_bridge.py                         # the bridge
ros2 run teleop_twist_keyboard teleop_twist_keyboard  # the keyboard
```

**Dry run** — nothing reaches the dog, the bridge sends to a test topic instead:

```bash
python3 go2_cmd_vel_bridge.py --ros-args -r /api/sport/request:=/dryrun
ros2 topic echo /dryrun    # hold i: api_id 1008 with x=0.3; let go: one api_id 1003 (StopMove)
```
