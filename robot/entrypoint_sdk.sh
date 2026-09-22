#!/bin/bash
# Load ROS, point rmw_zenoh at a router, then run whatever was asked for.
#
# ROUTER is where the zenoh router lives - the pod, reached through a port-forward on the
# laptop, e.g. ROUTER=tcp/192.168.0.135:7447. Without it the node looks for a router on
# localhost and finds none.
#
# ROS_DOMAIN_ID picks which robot this is. The simulation is 0, so a real dog gets its own
# (5 by default): the operator switches targets by changing this one variable.
set -e

source /opt/ros/jazzy/setup.bash

export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_zenoh_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-5}"

if [ -n "$ROUTER" ]; then
  cat > /tmp/zenoh_session.json5 <<EOF
{
  mode: "client",
  connect: { endpoints: ["$ROUTER"] },
}
EOF
  export ZENOH_SESSION_CONFIG_URI=/tmp/zenoh_session.json5
  echo "zenoh router: $ROUTER (domain $ROS_DOMAIN_ID)"
else
  echo "no ROUTER set - expecting a local rmw_zenohd (domain $ROS_DOMAIN_ID)"
fi

exec "$@"
