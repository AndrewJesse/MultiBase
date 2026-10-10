#!/usr/bin/env bash
# Stop AWS spend. Default is --pause (stop instances; EBS volumes still bill ~cents/day).
#   scripts/stop.sh            pause: stop EC2 instances in both regions
#   scripts/stop.sh --destroy  destroy the compute stack (only S3/state/IAM/budget remain)
#   scripts/stop.sh --audit    only report what is still billable
# Add --yes to skip the prompt.
source "$(dirname "$0")/lib.sh"
MODE=pause
for a in "$@"; do
  case "$a" in
    --pause) MODE=pause ;;
    --destroy) MODE=destroy ;;
    --audit) MODE=audit ;;
    --yes) ASSUME_YES=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done
require_aws

backup_first() {
  command -v kubectl >/dev/null || return 0
  kubectl get ns databases >/dev/null 2>&1 || return 0
  log "Requesting a final CloudNativePG backup (best effort)"
  kubectl -n databases apply -f - >/dev/null 2>&1 <<EOF || warn "backup request failed; continuing"
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: pre-stop-
  namespace: databases
spec:
  method: plugin
  cluster: { name: supabase-pg }
  pluginConfiguration: { name: barman-cloud.cloudnative-pg.io }
EOF
  kubectl -n databases wait backup --all --for=jsonpath='{.status.phase}'=completed --timeout=300s >/dev/null 2>&1 \
    || warn "backup did not complete in time"
}

remove_tailnet_devices() {
  [[ -n "${TS_API_KEY:-}" && -n "${TS_TAILNET:-}" ]] || { warn "TS_API_KEY/TS_TAILNET unset; remove mb-* devices manually if not ephemeral"; return 0; }
  curl -fsS -u "$TS_API_KEY:" "https://api.tailscale.com/api/v2/tailnet/$TS_TAILNET/devices" \
    | jq -r '.devices[] | select(.hostname|startswith("mb-")) | .id' \
    | while read -r id; do
        log "Deleting tailnet device $id"
        curl -fsS -X DELETE -u "$TS_API_KEY:" "https://api.tailscale.com/api/v2/device/$id" >/dev/null
      done
}

audit() {
  local bad=0 gb_total=0
  for r in "${REGIONS[@]}"; do
    run=$(instances "$r" pending,running,stopping | wc -w | tr -d ' ')
    vols=$(aws ec2 describe-volumes --region "$r" --filters Name=tag:Project,Values=multibase \
      --query 'Volumes[].Size' --output text | tr '\t' '\n' | awk '{s+=$1} END{print s+0}')
    eips=$(aws ec2 describe-addresses --region "$r" --filters Name=tag:Project,Values=multibase \
      --query 'length(Addresses)' --output text)
    nats=$(aws ec2 describe-nat-gateways --region "$r" --filter Name=state,Values=available,pending \
      --query 'length(NatGateways)' --output text)
    lbs=$(aws elbv2 describe-load-balancers --region "$r" --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0)
    snaps=$(aws ec2 describe-snapshots --region "$r" --owner-ids self --filters Name=tag:Project,Values=multibase \
      --query 'length(Snapshots)' --output text)
    printf '%-10s running=%s ebs_gb=%s eips=%s nat=%s elb=%s snapshots=%s\n' "$r" "$run" "$vols" "$eips" "$nats" "$lbs" "$snaps"
    gb_total=$((gb_total + vols))
    [[ "$run" != 0 || "$eips" != 0 || "$nats" != 0 || "$lbs" != 0 ]] && bad=1
    [[ "$MODE" == destroy && ( "$vols" != 0 || "$snaps" != 0 ) ]] && bad=1
  done
  # gp3 is about $0.08/GB-month
  awk -v g="$gb_total" 'BEGIN{printf "Residual EBS: %d GB ~ $%.2f/month (plus pennies of S3)\n", g, g*0.08}'
  if [[ "$bad" == 1 ]]; then warn "billable resources still present"; return 1; fi
  log "No compute charges accruing"
}

case "$MODE" in
  audit) audit ;;
  pause)
    confirm "Stop all MultiBase EC2 instances in ${REGIONS[*]}?" || exit 1
    backup_first
    for r in "${REGIONS[@]}"; do
      ids="$(instances "$r" pending,running)"
      [[ -z "$ids" ]] && continue
      log "Stopping $ids in $r"
      # shellcheck disable=SC2086
      aws ec2 stop-instances --region "$r" --instance-ids $ids >/dev/null
      # shellcheck disable=SC2086
      aws ec2 wait instance-stopped --region "$r" --instance-ids $ids
    done
    audit
    ;;
  destroy)
    confirm "DESTROY compute stack (instances, EBS, VPCs) in ${REGIONS[*]}? Data is restored from S3 on next start." || exit 1
    backup_first
    remove_tailnet_devices
    [[ -f "$TF_DIR/compute/backend.hcl" ]] || die "run scripts/bootstrap.sh first"
    tf_init compute
    terraform -chdir="$TF_DIR/compute" destroy -input=false -auto-approve
    audit
    ;;
esac
