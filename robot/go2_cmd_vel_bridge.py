#!/usr/bin/env python3
"""Drive a Unitree Go2 with /cmd_vel (e.g. from teleop_twist_keyboard).

Turns geometry_msgs/Twist into the Go2 sport-mode Move command on
/api/sport/request, the same request unitree_ros2's SportClient::Move sends.
If no /cmd_vel arrives for `timeout` seconds the dog is told to stop, so
letting go of the key (or killing teleop) halts it. Ctrl+C here stops it too.

Run after `source ~/unitree_ros2/setup.sh`:
    python3 go2_cmd_vel_bridge.py
Dry run (nothing reaches the dog, watch with `ros2 topic echo /dryrun`):
    python3 go2_cmd_vel_bridge.py --ros-args -r /api/sport/request:=/dryrun
"""
import json
import time

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from rclpy.signals import SignalHandlerOptions
from unitree_api.msg import Request

API_STOPMOVE = 1003
API_MOVE = 1008


def clamp(value, limit):
    return max(-limit, min(limit, value))


class CmdVelBridge(Node):
    def __init__(self):
        super().__init__('go2_cmd_vel_bridge')
        # Speed caps, deliberately low for a first test.
        self.max_vx = self.declare_parameter('max_vx', 0.3).value    # m/s forward/back
        self.max_vy = self.declare_parameter('max_vy', 0.2).value    # m/s sideways
        self.max_wz = self.declare_parameter('max_wz', 0.6).value    # rad/s turning
        self.timeout = self.declare_parameter('timeout', 1.0).value  # s without /cmd_vel -> stop

        self.pub = self.create_publisher(Request, '/api/sport/request', 10)
        # Relative, so -r __ns:=/dog1 makes this /dog1/cmd_vel. The remap is the documented
        # ROS 2 way; an earlier attempt used ROS_NAMESPACE and never produced a namespaced
        # topic, though a stale container muddied that test.
        self.create_subscription(Twist, 'cmd_vel', self.on_cmd_vel, 10)
        # teleop_twist_keyboard only publishes on key presses, so resend the
        # latest command at 10 Hz for as long as it is fresh.
        self.create_timer(0.1, self.tick)

        self.last_cmd = (0.0, 0.0, 0.0)
        self.last_time = None
        self.moving = False
        self.get_logger().info(
            f'limits vx={self.max_vx} vy={self.max_vy} wz={self.max_wz}, '
            f'stop after {self.timeout}s without /cmd_vel')

    def on_cmd_vel(self, msg):
        self.last_cmd = (clamp(msg.linear.x, self.max_vx),
                         clamp(msg.linear.y, self.max_vy),
                         clamp(msg.angular.z, self.max_wz))
        self.last_time = self.get_clock().now()

    def tick(self):
        if self.last_time is None:
            return
        age = (self.get_clock().now() - self.last_time).nanoseconds / 1e9
        if age > self.timeout or self.last_cmd == (0.0, 0.0, 0.0):
            if self.moving:
                self.send(API_STOPMOVE)
                self.moving = False
                self.get_logger().info('stop')
            return
        vx, vy, wz = self.last_cmd
        self.send(API_MOVE, json.dumps({'x': vx, 'y': vy, 'z': wz}))
        self.moving = True

    def send(self, api_id, parameter=''):
        req = Request()
        req.header.identity.api_id = api_id
        req.parameter = parameter
        self.pub.publish(req)


def main():
    # Keep the ROS context alive on Ctrl+C so the final StopMove can go out.
    rclpy.init(signal_handler_options=SignalHandlerOptions.NO)
    node = CmdVelBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.send(API_STOPMOVE)
        time.sleep(0.2)
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
