#!/usr/bin/env bash
# Bring the AWS nodes up. Resumes paused instances, or creates them if destroyed.
# Usage: TS_AUTHKEY=tskey-auth-... scripts/start.sh [--yes]
source "$(dirname "$0")/lib.sh"
[[ "${1:-}" == "--yes" ]] && ASSUME_YES=1
require_aws
[[ -f "$TF_DIR/compute/backend.hcl" ]] || die "run scripts/bootstrap.sh first"

if [[ -n "${TS_AUTHKEY:-}" ]]; then
  for r in "${REGIONS[@]}"; do
    log "Storing Tailscale auth key in SSM ($r)"
    aws ssm put-parameter --region "$r" --name /multibase/ts-authkey --type SecureString \
      --overwrite --value "$TS_AUTHKEY" >/dev/null
  done
elif [[ -z "$(for r in "${REGIONS[@]}"; do instances "$r" "pending,running,stopped,stopping"; done)" ]]; then
  die "no existing nodes; set TS_AUTHKEY (use an ephemeral, tagged, reusable key)"
fi

for r in "${REGIONS[@]}"; do
  stopped="$(instances "$r" stopped)"
  if [[ -n "$stopped" ]]; then
    log "Resuming $stopped in $r"
    # shellcheck disable=SC2086
    aws ec2 start-instances --region "$r" --instance-ids $stopped >/dev/null
  fi
done

log "Applying compute stack"
tf_init compute
terraform -chdir="$TF_DIR/compute" apply -input=false -auto-approve

for r in "${REGIONS[@]}"; do
  ids="$(instances "$r" pending,running)"
  log "Waiting for status checks in $r"
  # shellcheck disable=SC2086
  aws ec2 wait instance-status-ok --region "$r" --instance-ids $ids
done

log "Nodes are up. Verify with: tailscale status | grep mb-"
log "Remember: this costs money until you run scripts/stop.sh"
