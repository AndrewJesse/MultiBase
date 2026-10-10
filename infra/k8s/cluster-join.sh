#!/usr/bin/env bash
# Form the 3-node MicroK8s cluster over tailnet hostnames and fix the Calico MTU.
# Run from a machine on the tailnet. Hostnames: mb-us-east-1 (first node), mb-eu-west-1, mb-home.
set -euo pipefail
FIRST=mb-us-east-1
for peer in mb-eu-west-1 mb-home; do
  join=$(ssh ubuntu@$FIRST "microk8s add-node --format short" | head -1)
  ssh "ubuntu@$peer" "microk8s join $join"
done
ssh ubuntu@$FIRST "microk8s kubectl -n kube-system patch configmap calico-config --type merge -p '{\"data\":{\"veth_mtu\":\"1230\"}}' && microk8s kubectl -n kube-system rollout restart ds/calico-node"
ssh ubuntu@$FIRST "microk8s enable ha-cluster >/dev/null 2>&1 || true; microk8s kubectl get nodes"
