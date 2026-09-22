#!/usr/bin/env python3
"""Drive a Unitree Go2 with /cmd_vel, without unitree_ros2 on the ROS side.

Same job as go2_cmd_vel_bridge.py, one difference that matters: the dog is reached
through unitree_sdk2py instead of the /api/sport/request ROS topic. The SDK opens its
own CycloneDDS session inside this process, so the ROS side is free to use any
middleware - in particular rmw_zenoh, which cannot talk to the dog's DDS at all.

    ROS /cmd_vel (rmw_zenoh)  ->  this process  ->  SDK/CycloneDDS  ->  dog

That removes three problems at once: no zenoh<->DDS bridge beside the container, no
CycloneDDS to configure for ROS, and no Humble-vs-Jazzy type-hash mismatch, because
the SDK does not use ROS message types.

Run it with the interface that faces the dog (the same one unitree_ros2 uses):

    export RMW_IMPLEMENTATION=rmw_zenoh_cpp      # or any other, it no longer matters
    python3 go2_cmd_vel_sdk_bridge.py --iface eth0

Dry run, nothing reaches the dog:

    python3 go2_cmd_vel_sdk_bridge.py --iface eth0 --dry-run

Tested on a real dog on 2026-09-22, driven by teleop running in a RAP pod. Keep the remote
in your hand anyway.
"""
import argparse
import sys

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from rclpy.signals import SignalHandlerOptions

from unitree_sdk2py.core.channel import ChannelFactoryInitialize
from unitree_sdk2py.go2.sport.sport_client import SportClient


def clamp(value, limit):
    return max(-limit, min(limit, value))


class CmdVelSdkBridge(Node):
    def __init__(self, client, dry_run):
        super().__init__('go2_cmd_vel_sdk_bridge')
        self.client = client
        self.dry_run = dry_run

        # Same caps as the ROS-side bridge, deliberately low.
        self.max_vx = self.declare_parameter('max_vx', 0.3).value    # m/s forward/back
        self.max_vy = self.declare_parameter('max_vy', 0.2).value    # m/s sideways
        self.max_wz = self.declare_parameter('max_wz', 0.6).value    # rad/s turning
        self.timeout = self.declare_parameter('timeout', 1.0).value  # s without /cmd_vel -> stop

        # Relative, not '/cmd_vel': with ROS_NAMESPACE=dog1 this becomes /dog1/cmd_vel, so
        # several dogs can share one domain and one operator node can address them all.
        self.create_subscription(Twist, 'cmd_vel', self.on_cmd_vel, 10)
        # teleop_twist_keyboard only publishes on key presses, so resend the latest
        # command at 10 Hz for as long as it is fresh - Move is a one-shot command.
        self.create_timer(0.1, self.tick)

        self.last_cmd = (0.0, 0.0, 0.0)
        self.last_time = None
        self.moving = False
        self.get_logger().info(
            f'limits vx={self.max_vx} vy={self.max_vy} wz={self.max_wz}, '
            f'stop after {self.timeout}s without /cmd_vel'
            + (' [DRY RUN]' if dry_run else ''))

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
                self.stop()
                self.moving = False
                self.get_logger().info('stop')
            return
        self.move(*self.last_cmd)
        self.moving = True

    def move(self, vx, vy, wz):
        if self.dry_run:
            self.get_logger().info(f'Move({vx:.2f}, {vy:.2f}, {wz:.2f})')
            return
        self.client.Move(vx, vy, wz)

    def stop(self):
        if self.dry_run:
            self.get_logger().info('StopMove()')
            return
        self.client.StopMove()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--iface', required=True, help='network interface facing the dog')
    parser.add_argument('--dry-run', action='store_true', help='log commands, send nothing')
    args, ros_args = parser.parse_known_args()

    client = None
    if not args.dry_run:
        # domain 0 on the dog's own network, exactly what unitree_ros2's setup.sh configures
        ChannelFactoryInitialize(0, args.iface)
        client = SportClient()
        client.SetTimeout(10.0)
        client.Init()

    rclpy.init(args=ros_args, signal_handler_options=SignalHandlerOptions.NO)
    node = CmdVelSdkBridge(client, args.dry_run)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.stop()          # never leave the dog walking
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    sys.exit(main())
