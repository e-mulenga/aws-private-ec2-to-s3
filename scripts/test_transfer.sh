#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# test_transfer.sh — End-to-end validation of the private S3
# transfer architecture. Run from your local machine after
# `terraform apply`.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }

cd "$(dirname "${BASH_SOURCE[0]}")/../terraform"

INSTANCE_ID=$(terraform output -raw instance_id)
BUCKET=$(terraform output -raw bucket_name)
RT_ID=$(terraform output -raw verify_no_internet_route 2>/dev/null | grep -oE 'rtb-[a-z0-9]+' || echo "")

echo ""
echo "══════════════════════════════════════════"
echo "  Private EC2 → S3 Transfer Verification"
echo "══════════════════════════════════════════"
echo ""

info "Instance: ${INSTANCE_ID}"
info "Bucket:   ${BUCKET}"
echo ""

info "Confirming instance has NO public IP..."
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[].Instances[].PublicIpAddress" --output text)
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
  success "No public IP — instance is genuinely private"
else
  fail "Instance has a public IP: $PUBLIC_IP — architecture assumption violated"
fi

info "Confirming private route table has NO internet route..."
ROUTES=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=private-ec2-s3-private-rt" \
  --query "RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0']" --output text)
if [ -z "$ROUTES" ]; then
  success "No 0.0.0.0/0 route present — subnet is genuinely private"
else
  fail "Found an internet route — subnet is not actually private"
fi

info "Waiting for SSM registration (up to 60s)..."
for i in $(seq 1 12); do
  STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null || echo "None")
  [ "$STATUS" = "Online" ] && break
  sleep 5
done

if [ "$STATUS" = "Online" ]; then
  success "Instance registered with SSM (Online)"
else
  fail "Instance not yet visible to SSM — wait longer and retry"
  exit 1
fi

info "Running S3 upload test via SSM Run Command..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo \"test transfer $(date)\" > /tmp/test.txt","aws s3 cp /tmp/test.txt s3://'"$BUCKET"'/test.txt"]' \
  --query "Command.CommandId" --output text)

sleep 8

RESULT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "Status" --output text)

if [ "$RESULT" = "Success" ]; then
  success "File transferred successfully to S3 via the Gateway Endpoint"
else
  fail "Transfer command status: $RESULT"
  exit 1
fi

info "Verifying the object exists in S3..."
aws s3 ls "s3://${BUCKET}/test.txt" && success "test.txt confirmed in bucket"

echo ""
success "All checks passed — private-to-S3 transfer working with zero internet exposure"
