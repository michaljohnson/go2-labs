#!/usr/bin/env python3
"""Measure the round trip from an operator to a robot and back, through ROS.

Two halves. The echo runs where the robot is, the measure runs where the operator is:

    robot side     python3 latency_probe.py echo
    operator side  python3 latency_probe.py measure --count 200 --rate 10

Both need the same ROS_DOMAIN_ID (and namespace, if any) and the same middleware - i.e.
exactly the setup the teleop uses, so the number describes the real control path and not a
raw socket. Run it on each platform you are comparing and put the columns side by side.

The timestamp is written and read by the same clock on the operator side, so the two
machines do not need synchronised clocks. What it reports is the full loop:

    publish -> zenoh router -> robot -> echo -> back -> subscribe

A one-way delay is roughly half of it, and the tail (p95, max) matters more than the
median: a control loop is hurt by the late messages, not the average ones.
"""
import argparse
import statistics
import sys

import rclpy
from rclpy.node import Node
from std_msgs.msg import Header


class Echo(Node):
    """Bounce every message straight back."""

    def __init__(self):
        super().__init__('latency_echo')
        self.pub = self.create_publisher(Header, 'probe_echo', 10)
        self.create_subscription(Header, 'probe', lambda m: self.pub.publish(m), 10)
        self.get_logger().info('echoing probe -> probe_echo')


class Measure(Node):
    def __init__(self, count, rate):
        super().__init__('latency_measure')
        self.count = count
        self.sent = 0
        self.rtt = []
        self.pub = self.create_publisher(Header, 'probe', 10)
        self.create_subscription(Header, 'probe_echo', self.on_echo, 10)
        self.create_timer(1.0 / rate, self.tick)
        self.get_logger().info(f'sending {count} probes at {rate} Hz')

    def tick(self):
        if self.sent >= self.count:
            return
        msg = Header()
        msg.stamp = self.get_clock().now().to_msg()
        msg.frame_id = str(self.sent)
        self.pub.publish(msg)
        self.sent += 1

    def on_echo(self, msg):
        sent = msg.stamp.sec + msg.stamp.nanosec / 1e9
        now = self.get_clock().now().nanoseconds / 1e9
        self.rtt.append((now - sent) * 1000.0)   # ms
        if len(self.rtt) >= self.count:
            self.report()
            raise SystemExit(0)

    def report(self):
        r = sorted(self.rtt)
        lost = self.count - len(r)
        print(f'\nround trip over {len(r)} messages ({lost} lost)')
        print(f'  median {statistics.median(r):6.1f} ms')
        print(f'  p95    {r[int(len(r) * 0.95) - 1]:6.1f} ms')
        print(f'  max    {r[-1]:6.1f} ms')
        print(f'  min    {r[0]:6.1f} ms')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('role', choices=['echo', 'measure'])
    parser.add_argument('--count', type=int, default=200, help='messages to send (measure)')
    parser.add_argument('--rate', type=float, default=10.0, help='send rate in Hz (measure)')
    args, ros_args = parser.parse_known_args()

    rclpy.init(args=ros_args)
    node = Echo() if args.role == 'echo' else Measure(args.count, args.rate)
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        # Ctrl+C before the last echo still reports what did come back - and nothing at
        # all means the echo side never reached us, which is the useful answer.
        if isinstance(node, Measure):
            node.report() if node.rtt else print('\nno echoes came back')
        node.destroy_node()
        if rclpy.ok():       # rclpy's own signal handler may already have shut down
            rclpy.shutdown()


if __name__ == '__main__':
    sys.exit(main())
