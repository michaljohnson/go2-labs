#!/usr/bin/env python3
"""Write worlds/lab.sdf: the sensor-free world turned into a room to walk the dog in.

The default world is an empty plane, so a walking dog looks like a dog walking on the
spot. This adds a 12 x 8 m hall with an outer wall, a dividing wall with a doorway, and
a few crates - somewhere to drive to, get lost in, and later map.

Everything is static and made of boxes, so it costs no dynamics and downloads nothing.
A Fuel world would look nicer but pulls models per student and brings back the sensor
plugin the pod can't render.

Built by patching headless.sdf, so the system plugins the launch file expects (physics,
scene broadcaster, IMU, user commands) stay exactly as upstream has them.
"""
import pathlib

WORLDS = pathlib.Path.home() / 'rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_description/worlds'

H = 1.0   # wall height
T = 0.2   # wall thickness

# name, centre x, centre y, size x, size y, size z. The dog spawns at the origin,
# which sits in the middle of the west room with clear space around it.
BOXES = [
    ("wall_north", 0.0, 4.0, 12.0, T, H),
    ("wall_south", 0.0, -4.0, 12.0, T, H),
    ("wall_west", -6.0, 0.0, T, 8.0, H),
    ("wall_east", 6.0, 0.0, T, 8.0, H),
    # dividing wall at x = 2 with a 1.6 m doorway between y = -0.8 and y = 0.8
    ("wall_divide_n", 2.0, 2.4, T, 3.2, H),
    ("wall_divide_s", 2.0, -2.4, T, 3.2, H),
    # crates to walk around
    ("crate_1", -3.0, 2.0, 0.6, 0.6, 0.6),
    ("crate_2", -2.0, -2.5, 0.8, 0.8, 0.4),
    ("crate_3", 4.0, 1.5, 0.6, 0.6, 0.6),
    ("crate_4", 4.5, -2.0, 1.0, 0.5, 0.5),
]

MODEL = """
    <model name="{name}">
      <static>true</static>
      <pose>{x} {y} {z} 0 0 0</pose>
      <link name="link">
        <collision name="collision">
          <geometry><box><size>{sx} {sy} {sz}</size></box></geometry>
        </collision>
        <visual name="visual">
          <geometry><box><size>{sx} {sy} {sz}</size></box></geometry>
          <material><diffuse>{colour}</diffuse></material>
        </visual>
      </link>
    </model>
"""


def main():
    src = WORLDS / 'headless.sdf'
    dst = WORLDS / 'lab.sdf'

    models = "".join(
        MODEL.format(
            name=name, x=x, y=y, z=sz / 2, sx=sx, sy=sy, sz=sz,
            colour="0.7 0.7 0.7 1" if name.startswith("wall") else "0.8 0.5 0.1 1",
        )
        for name, x, y, sx, sy, sz in BOXES
    )
    dst.write_text(src.read_text().replace('</world>', f'{models}  </world>'))
    print(f'{dst}: hall with {len(BOXES)} boxes written')


if __name__ == '__main__':
    main()
