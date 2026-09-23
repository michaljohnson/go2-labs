# Unitree Go2 labs — CAS Physical AI & Robotics, Module C

Two labs with the Unitree Go2: **lab 1 in simulation** on the RAP cluster, **lab 2 on the real
dog**. Both use the same interface, so your node works in either place unchanged:

```
your node ──/cmd_vel──►  simulation: CHAMP controller walks the legs
                    └─►  real dog:   go2_cmd_vel_bridge → /api/sport/request
```

That is the whole point of the setup: `geometry_msgs/Twist` on `/cmd_vel`, nothing else.

| Folder | Contents |
|---|---|
| `docs/lab1-sim.md` | lab 1: the Go2 in Gazebo on RAP — setup, starting it, what to watch out for |
| `docs/sim-quickstart.md` | the simulation terminal by terminal, for starting it by hand |
| `docs/lab2-real.md` | lab 2: the real dog — the Jetson, the bridge, safety |
| `docs/driving-a-dog.md` | the two ways a pod reaches a real dog, terminal by terminal |
| `docs/jetsons.md` | which Jetson drives which dog, how to set one up, and how to stop one cleanly |
| `sim/` | `setup.sh` builds the simulation workspace; patches we need on the cluster |
| `robot/` | robot side: `/cmd_vel` bridge, Docker image, start scripts |
| `viz/` | seeing it from your own laptop (Lichtblick / Foxglove) |

## What you need

- **Lab 1:** an account for the RAP cluster and its pod; everything else is installed by `sim/setup.sh`
- **Lab 2:** the dog, its Jetson, and the remote control in your hand

## Upstream projects

We don't copy their instructions — read them at the source:

- [khaledgabr77/unitree_go2_ros2](https://github.com/khaledgabr77/unitree_go2_ros2) — Go2 in
  Gazebo (ROS 2 Jazzy, Gazebo Harmonic, CHAMP locomotion). `sim/setup.sh` pins it to a fixed commit.
- [unitreerobotics/unitree_ros2](https://github.com/unitreerobotics/unitree_ros2) — Unitree's own
  ROS 2 messages for the real dog. Its README is written for Foxy; read `humble` wherever it says `foxy`.
- [Lichtblick](https://github.com/lichtblick-suite/lichtblick) — open-source viewer, no account needed.
- [RAP-EN/random_walk](https://github.zhaw.ch/RAP-EN/random_walk) — the random-walk node used in
  lab 1. Clone it into your own workspace; it is not part of this repo.