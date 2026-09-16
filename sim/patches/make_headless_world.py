#!/usr/bin/env python3
"""Write worlds/headless.sdf: the default world without the sensor plugin.

gz-sim-sensors-system renders (cameras, lidar) and needs /dev/dri, which the RAP pod denies -
the server then dies with "libEGL ... Permission denied". Without the plugin the dog walks, it
just has no sensors. For Nav2 we need them back, and then the pod needs access to the GPU device.
"""
import pathlib
import re

worlds = pathlib.Path.home() / 'rap/cas/go2_ws/src/unitree_go2_ros2/unitree_go2_description/worlds'
src = worlds / 'default.sdf'
dst = worlds / 'headless.sdf'

text = src.read_text()
stripped = re.sub(r'\s*<plugin[^>]*filename="gz-sim-sensors-system".*?</plugin>', '', text, flags=re.S)
dst.write_text(stripped)
print(f'{dst}: sensor plugin removed: {text != stripped}')
