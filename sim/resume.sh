#!/bin/bash
# Put back what a pod restart wipes. Everything outside ~/rap is ephemeral: apt packages,
# ~/.ssh, ~/.bashrc. The workspace itself survives, so this is quick.
#
#   ./sim/resume.sh          # ssh + env line
#   ./sim/resume.sh --viz    # also foxglove_bridge, for the Lichtblick lab
#
# Nothing here is needed to run the simulation from the pod's own desktop - only to reach
# the pod from outside. The proper fix is to have these in the image; until then, this.
set -e

sudo apt-get update -qq

BACKUP="$HOME/rap/authorized_keys.backup"
ENVLINE='source ~/rap/cas/go2-labs/sim/env.sh'

echo "== ssh server"
if ! command -v sshd >/dev/null && [ ! -x /usr/sbin/sshd ]; then
  sudo apt-get update -qq && sudo apt-get install -y -qq openssh-server
fi
sudo mkdir -p /run/sshd && sudo chmod 0755 /run/sshd   # privilege separation dir, empty on a fresh container
sudo ssh-keygen -A                      # host keys, or sshd closes every connection
pgrep sshd >/dev/null || sudo /usr/sbin/sshd
pgrep -a sshd | head -1

echo "== authorised keys"
if [ -f "$BACKUP" ]; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  cp "$BACKUP" "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
  echo "restored from $BACKUP"
else
  echo "no $BACKUP - add your key there once, it lives on the persistent volume"
fi

echo "== render group"
# supplementalGroups (110) reaches processes the container starts - kubectl exec, the
# desktop - but NOT an ssh login, which builds its groups from /etc/group. Without it the
# GPU render nodes are unreadable and gz-sim-sensors-system fails in ssh sessions only.
sudo usermod -aG 110 ros 2>/dev/null && echo "ros added to gid 110 (log in again for it to apply)"

echo "== shell setup"
grep -qF "$ENVLINE" "$HOME/.bashrc" || echo "$ENVLINE" >> "$HOME/.bashrc"
echo "ok"

if [ "$1" = "--viz" ]; then
  echo "== foxglove bridge"
  sudo apt-get install -y -qq ros-jazzy-foxglove-bridge
fi

echo
echo "Done. New terminals are set up; ssh works once your port-forward is running."
