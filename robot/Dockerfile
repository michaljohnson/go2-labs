# Robot-side image for the Unitree Go2: unitree_ros2 messages, CycloneDDS and
# keyboard teleop. Runs on the Go2's Jetson, which is cabled to the dog's
# internal network (192.168.123.x, dog's main board at .161).
#
# ros:humble-ros-base is published for arm64, so on the Jetson this is a normal
# build, no emulation:   docker build -t cas-go2-robot robot/
#
# Humble because unitree_ros2 is tested on Foxy/Humble only. Jazzy should work
# too (same CycloneDDS 0.10 line as the dog) but is untested:
#   docker build --build-arg ROS_DISTRO=jazzy -t cas-go2-robot robot/
ARG ROS_DISTRO=humble
FROM ros:${ROS_DISTRO}-ros-base

SHELL ["/bin/bash", "-c"]
WORKDIR /ws

# Pin to a fixed commit for the course, so an upstream change can't break it mid-term.
ARG UNITREE_ROS2_REF=668d1ec5a05d1c38d3306bdca7d59f2ba3581a88

# rmw-cyclonedds-cpp, rosidl-generator-dds-idl, libyaml-cpp-dev: unitree_ros2's
# dependencies (its README, step 1). The dog speaks CycloneDDS, so ROS must too.
# iproute2: entrypoint.sh uses `ip` to find the port that leads to the dog.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-rmw-cyclonedds-cpp ros-${ROS_DISTRO}-rosidl-generator-dds-idl \
      libyaml-cpp-dev iproute2 ros-${ROS_DISTRO}-teleop-twist-keyboard && \
    rm -rf /var/lib/apt/lists/*

# Only the message packages the Go2 needs (unitree_hg is for the humanoids).
# On Humble the README's "compile cyclonedds" step is skipped, as it says.
RUN git clone https://github.com/unitreerobotics/unitree_ros2.git /tmp/unitree_ros2 && \
    git -C /tmp/unitree_ros2 checkout "$UNITREE_ROS2_REF" && \
    mkdir -p src && mv /tmp/unitree_ros2/cyclonedds_ws/src/unitree src/ && \
    rm -rf /tmp/unitree_ros2 && \
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    colcon build --packages-select unitree_go unitree_api && \
    rm -rf build log

COPY go2_cmd_vel_bridge.py /usr/local/bin/go2_cmd_vel_bridge
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default: the /cmd_vel -> sport-mode bridge. Drive it with teleop.sh.
CMD ["go2_cmd_vel_bridge"]
