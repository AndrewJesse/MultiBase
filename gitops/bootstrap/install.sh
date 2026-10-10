#!/usr/bin/env bash
# Install Argo CD and the root app-of-apps. Needs kubectl pointed at the cluster.
set -euo pipefail
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -f "$(dirname "$0")/root-app.yaml"
