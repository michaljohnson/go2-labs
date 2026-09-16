# Seeing it from your own laptop

In the pod, Gazebo and RViz run on the noVNC desktop (see [`../docs/lab1-sim.md`](../docs/lab1-sim.md)).
The alternative is a viewer on your own laptop that connects to the ROS system over a WebSocket —
the same approach works for the simulation and for the real dog.

We use **[Lichtblick](https://github.com/lichtblick-suite/lichtblick)**, an open-source fork of
Foxglove Studio: same protocol, no account, no cloud. Foxglove itself works too, but wants a
sign-in per student.

**On the robot side** (in the pod, or on the Jetson with `ros-humble-foxglove-bridge`):
```bash
sudo apt install -y ros-jazzy-foxglove-bridge
ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765
```

**On the laptop**, for the cluster, forward the port:
```bash
kubectl -n <your-namespace> port-forward deploy/rap-deployment 8765:8765
```
(`<your-namespace>` is your own RAP namespace, e.g. `rap-9`.)
With the real dog you connect straight to its address, no forwarding needed.

**In Lichtblick:** *Open connection* → *Foxglove WebSocket* → `ws://localhost:8765`

**A view worth having:** a **3D** panel with Fixed Frame `odom`, the robot model from
`/robot_description` and `/tf`; a **Plot** panel on `/cmd_vel`. Save the layout and you can hand it
to students as a file.
