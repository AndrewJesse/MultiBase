#!/usr/bin/env bash
# Home node (node 3): join the tailnet and MicroK8s. Run on an Ubuntu 24.04 machine.
# Usage: sudo TS_AUTHKEY=tskey-... ./setup.sh
set -euo pipefail
: "${TS_AUTHKEY:?}"
apt-get update && apt-get install -y curl jq
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey "$TS_AUTHKEY" --hostname mb-home --ssh --advertise-tags=tag:node
snap install microk8s --classic --channel=1.32/stable
usermod -aG microk8s "${SUDO_USER:-ubuntu}"
microk8s status --wait-ready
microk8s enable dns hostpath-storage helm
