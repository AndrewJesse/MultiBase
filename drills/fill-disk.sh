#!/usr/bin/env bash
# Drill 3: fill the disk on a Postgres node. Usage: drills/fill-disk.sh <node-hostname> [GB]
# Runs over Tailscale SSH. Writes to /var/tmp, which shares the root volume; cleanup runs on exit.
set -euo pipefail
node=${1:?node hostname}; gb=${2:-20}
trap 'ssh ubuntu@"$node" "rm -f /var/tmp/fill.bin"; echo cleaned' EXIT
echo "$(date -u +%FT%TZ) filling $gb GB on $node"
ssh ubuntu@"$node" "fallocate -l ${gb}G /var/tmp/fill.bin || dd if=/dev/zero of=/var/tmp/fill.bin bs=1M count=$((gb*1024))"
echo "Observe: NodeDiskAlmostFull alert, Postgres behaviour. Press Enter to clean up."; read -r
