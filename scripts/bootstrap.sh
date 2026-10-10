#!/usr/bin/env bash
# One-time setup: Terraform state bucket + persistent stack (S3 backups, IAM, budget).
# Usage: BUDGET_EMAIL=you@example.com scripts/bootstrap.sh
source "$(dirname "$0")/lib.sh"
require_aws
: "${BUDGET_EMAIL:?set BUDGET_EMAIL for the AWS Budgets alert}"

log "State bucket $STATE_BUCKET"
if ! aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$PRIMARY_REGION" >/dev/null
  aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

for stack in persistent compute; do
  cat >"$TF_DIR/$stack/backend.hcl" <<EOF
bucket       = "$STATE_BUCKET"
key          = "multibase/$stack.tfstate"
region       = "$PRIMARY_REGION"
use_lockfile = true
encrypt      = true
EOF
done

log "Applying persistent stack"
tf_init persistent
terraform -chdir="$TF_DIR/persistent" apply -input=false -auto-approve -var "budget_email=$BUDGET_EMAIL"
log "Bootstrap done. Next: TS_AUTHKEY=tskey-... scripts/start.sh"
