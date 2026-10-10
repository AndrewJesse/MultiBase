#!/usr/bin/env bash
# Drill 1: kill the CNPG primary and time the failover. Usage: drills/kill-primary.sh
set -euo pipefail
ns=databases; cluster=supabase-pg
primary=$(kubectl -n $ns get cluster $cluster -o jsonpath='{.status.currentPrimary}')
echo "$(date -u +%FT%TZ) deleting primary $primary"
start=$(date +%s)
kubectl -n $ns delete pod "$primary" --grace-period=0 --force
until [[ "$(kubectl -n $ns get cluster $cluster -o jsonpath='{.status.currentPrimary}')" != "$primary" ]] \
  && kubectl -n $ns get cluster $cluster -o jsonpath='{.status.phase}' | grep -q "healthy"; do sleep 1; done
echo "failover + recovery took $(( $(date +%s) - start ))s; new primary: $(kubectl -n $ns get cluster $cluster -o jsonpath='{.status.currentPrimary}')"
