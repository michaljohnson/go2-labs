#!/bin/bash
# Pack a built workspace so the next pod doesn't have to build it.
#
#   ./sim/pack_workspace.sh                  # writes ~/rap/go2_ws-prebuilt.tar.gz
#
# The result is about 20 MB and restores in seconds, against ~10 minutes of colcon per
# student. Attach it to a release of this repo and `setup.sh --prebuilt <url>` fetches it.
#
# It ships `src` as well as `install`, because the workspace is built with
# --symlink-install: install/ is mostly symlinks into src/. For the same reason the
# destination path must be identical to the source path - every pod uses
# /home/ros/rap/cas/go2_ws, so that holds here but would not on a laptop.
set -e

WS="$HOME/rap/cas/go2_ws"
OUT="${1:-$HOME/rap/go2_ws-prebuilt.tar.gz}"

[ -d "$WS/install" ] || { echo "No build in $WS - run ./sim/setup.sh first"; exit 1; }

echo "packing $WS -> $OUT"
tar czf "$OUT" -C "$(dirname "$WS")" "$(basename "$WS")/install" "$(basename "$WS")/src"

echo "$(du -h "$OUT" | cut -f1)  $OUT"
echo
echo "Restore it in another pod with:"
echo "  ./sim/setup.sh --prebuilt <url-or-path>"
