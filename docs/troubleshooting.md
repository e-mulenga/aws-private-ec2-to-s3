# 🔧 Troubleshooting

## "Unable to locate credentials" from the instance

**Cause:** IAM role not attached, or the SSM Agent hasn't picked it up yet.
```bash
aws ec2 describe-instances --instance-ids <id> \
  --query "Reservations[].Instances[].IamInstanceProfile"
```

## S3 upload hangs or times out

**Cause:** Gateway Endpoint not associated with the subnet's route table.
```bash
aws ec2 describe-route-tables --route-table-ids <rt-id> \
  --query "RouteTables[].Routes"
# Should show a route with a DestinationPrefixListId matching a vpce-*
```

## "Access Denied" on `s3 cp`

**Cause:** IAM policy doesn't cover the specific bucket/actions being used.
```bash
aws iam list-role-policies --role-name private-ec2-s3-instance-role-<account-id>
aws iam get-role-policy --role-name <role> --policy-name s3-transfer-policy
```

## Instance not visible in SSM

**Cause:** SSM Agent not running, or the SSM VPC endpoints (`ssm`,
`ssmmessages`, `ec2messages`) are missing if this pattern is extended to
a fully air-gapped VPC with no Gateway Endpoint reliance for SSM itself.
This project relies on the instance eventually installing/starting the
agent via user data — allow 1-2 minutes after `apply` before connecting.
