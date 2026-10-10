#!/usr/bin/env bash
# Drill 2: cut a node off with a Tailscale ACL change, then restore it.
# Usage: TS_API_KEY=... TS_TAILNET=... drills/partition-node.sh <tag-to-isolate-from-nodes, e.g. tag:isolated>
# Tag the target node as tag:isolated first; the isolating policy lives in drills/isolate-policy.hujson.
set -euo pipefail
: "${TS_API_KEY:?}" "${TS_TAILNET:?}"
api="https://api.tailscale.com/api/v2/tailnet/$TS_TAILNET/acl"
repo_policy="$(dirname "$0")/../infra/tailscale/policy.hujson"
iso_policy="$(dirname "$0")/isolate-policy.hujson"
push() { curl -fsS -u "$TS_API_KEY:" -H 'Content-Type: application/hujson' --data-binary @"$1" "$api" >/dev/null; }
trap 'echo restoring policy; push "$repo_policy"' EXIT
echo "$(date -u +%FT%TZ) applying isolation policy"; push "$iso_policy"
echo "Observe: replication lag, prober failures per site, CNPG status. Press Enter to restore."; read -r
