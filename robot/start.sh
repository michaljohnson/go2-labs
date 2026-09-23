#!/bin/bash
# Start everything a dog needs on its Jetson, in one tmux session.
#
#   ROUTER=tcp/<router-address>:32447 ./robot/start.sh
#   ./robot/start.sh stop
#   tmux attach -t dog          # watch the logs, Ctrl-b then 0/1/2 to switch
#
# Three windows, because three things have to be alive and any one of them dying takes the
# dog off the air silently - the topics stay visible in the pod either way, so a closed
# terminal looks exactly like a working robot until you publish into it:
#
#   0 bridge     the link to the zenoh router
#   1 dog        /cmd_vel -> sport-mode Move
#   2 telemetry  the dog's odometry and mode, back to the operator
#
# Detach with Ctrl-b then d and everything keeps running. That is the point: an ssh session
# dropping, a laptop lid closing or a wifi hiccup no longer stops a robot mid-lab.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SESSION="${SESSION:-dog}"

if [ "$1" = "stop" ]; then
  tmux kill-session -t "$SESSION" 2>/dev/null && echo "stopped" || echo "nothing was running"
  docker rm -f zbridge go2 go2-telemetry >/dev/null 2>&1 || true
  exit 0
fi

command -v tmux >/dev/null || { echo "tmux is missing: sudo apt install -y tmux"; exit 1; }
[ -n "$ROUTER" ] || { echo "set ROUTER, e.g. ROUTER=tcp/<router-address>:32447"; exit 1; }

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Already running - attaching. './robot/start.sh stop' ends it."
  exec tmux attach -t "$SESSION"
fi

# Leftovers from a previous run hold the container names, and a stray one still answering
# on /cmd_vel is a dog that obeys commands addressed to nobody.
docker rm -f zbridge go2 go2-telemetry >/dev/null 2>&1 || true

tmux new-session  -d -s "$SESSION" -n bridge    "ROUTER=$ROUTER $HERE/run_bridge.sh; read"
# The bridge first: the others announce themselves through it.
sleep 3
# "$SESSION:" with the colon - without it tmux reads the target as a window, not a
# session, and the second window fails with "index 1 in use".
tmux new-window   -t "$SESSION:" -n dog        "$HERE/run.sh; read"
tmux new-window   -t "$SESSION:" -n telemetry  "$HERE/run.sh telemetry; read"

echo "started in tmux session '$SESSION' - tmux attach -t $SESSION"
echo "Ctrl-b then 0/1/2 switches window, Ctrl-b then d detaches."
docker ps --format '  {{.Names}}\t{{.Status}}'
