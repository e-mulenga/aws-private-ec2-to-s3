output "instance_id" {
  description = "Private EC2 instance ID — connect via SSM"
  value       = aws_instance.private.id
}

output "bucket_name" {
  description = "Destination S3 bucket name"
  value       = aws_s3_bucket.destination.id
}

output "vpc_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "ssm_connect_command" {
  description = "Command to connect to the private instance"
  value       = "aws ssm start-session --target ${aws_instance.private.id} --region ${var.aws_region}"
}

output "test_upload_command" {
  description = "Run this from within the SSM session to test the transfer"
  value       = "echo 'test' > test.txt && aws s3 cp test.txt s3://${aws_s3_bucket.destination.id}/test.txt"
}

output "verify_no_internet_route" {
  description = "Confirms the private subnet has no route to the internet"
  value       = "aws ec2 describe-route-tables --route-table-ids ${aws_route_table.private.id} --query 'RouteTables[].Routes'"
}
