#!/usr/bin/env bash
# Shared helpers for the MultiBase scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/terraform"
REGIONS=(us-east-1 eu-west-1)
PRIMARY_REGION="${REGIONS[0]}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do command -v "$c" >/dev/null || die "missing required command: $c"; done
}

require_aws() {
  need aws terraform jq
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
    || die "AWS credentials not available (run 'aws login' or set AWS_PROFILE)"
  STATE_BUCKET="multibase-tfstate-${ACCOUNT_ID}"
}

confirm() {
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  read -r -p "$1 [y/N] " ans
  [[ "$ans" == y || "$ans" == Y ]]
}

# Instance ids for this project in a region, filtered by state (comma-separated).
instances() {
  aws ec2 describe-instances --region "$1" \
    --filters "Name=tag:Project,Values=multibase" "Name=tag:Stack,Values=compute" \
              "Name=instance-state-name,Values=$2" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

tf_init() { # <stack>
  terraform -chdir="$TF_DIR/$1" init -input=false -reconfigure -backend-config="$TF_DIR/$1/backend.hcl" >/dev/null
}
