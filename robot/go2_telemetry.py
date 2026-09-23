#!/usr/bin/env python3
"""Republish what the operator needs from the dog, in standard message types.

Two problems, one node.

The first is discovery. `zenoh-bridge-ros2dds` routes what it finds through
`ros_discovery_info`, and the dog's firmware speaks DDS without running `rcl` - it
announces no ROS nodes, so its topics never cross the bridge however generous the allow
list is. Verified on 23 Sep 2026: only /cmd_vel crossed, /lf/sportmodestate did not. This
node *is* an rcl node, so everything it publishes is discovered and routed normally.

The second is types. /sportmodestate is `unitree_go/msg/SportModeState`, and the pod has
no unitree_ros2 packages - even once the bytes arrive, `ros2 topic echo` there cannot
decode them. So the mode is republished as a std_msgs/UInt8, which any ROS install reads.
Odometry needs no translation: /utlidar/robot_odom is already nav_msgs/Odometry.

Run it on the Jetson, beside the /cmd_vel bridge:

    docker run --rm -it --network host --ipc host \
      -v ~/go2-labs/robot:/robot -e ROS_DOMAIN_ID=0 \
      cas-go2-robot /entrypoint.sh python3 /robot/go2_telemetry.py

Then add /odom and /mode to the bridge's allow list, or they stop at the Jetson.
"""
import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from std_msgs.msg import UInt8

from unitree_go.msg import SportModeState

# The dog publishes best-effort. A reliable subscription would simply never match, and the
# symptom is silence rather than an error - so ask for best-effort and take what comes.
SENSOR_QOS = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT,
                        history=HistoryPolicy.KEEP_LAST, depth=1)


class Telemetry(Node):
    def __init__(self):
        super().__init__('go2_telemetry')

        # Relative names, so ROS_NAMESPACE=dog1 gives /dog1/odom and /dog1/mode - the same
        # scheme the command side already uses for /dog1/cmd_vel.
        #
        # 'odom' on purpose: the simulation publishes /odom too, in the same nav_msgs type.
        # A student's node that plots /odom against /cmd_vel then works unchanged against
        # the sim and against a real dog, which is the whole point of the lab.
        self.odom_pub = self.create_publisher(Odometry, 'odom', 10)
        self.mode_pub = self.create_publisher(UInt8, 'mode', 10)

        self.create_subscription(Odometry, '/utlidar/robot_odom', self.on_odom, SENSOR_QOS)
        self.create_subscription(SportModeState, '/lf/sportmodestate', self.on_state, SENSOR_QOS)

        self.last_mode = None
        self.get_logger().info('republishing /utlidar/robot_odom -> odom, '
                               '/lf/sportmodestate -> mode')

    def on_odom(self, msg):
        self.odom_pub.publish(msg)

    def on_state(self, msg):
        self.mode_pub.publish(UInt8(data=int(msg.mode)))
        # 1 = balance stand (walks), 5 = lie down, 7 = damping. Worth saying out loud when
        # it changes: a dog that has dropped to 7 ignores every Move and looks broken.
        if msg.mode != self.last_mode:
            self.get_logger().info(f'mode {self.last_mode} -> {msg.mode}')
            self.last_mode = msg.mode


def main():
    rclpy.init()
    node = Telemetry()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
