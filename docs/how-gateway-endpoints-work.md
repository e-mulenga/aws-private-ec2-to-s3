# 🔍 How S3 Gateway VPC Endpoints Work

## The Problem Without an Endpoint

By default, S3 is accessed over its public endpoint
(`s3.<region>.amazonaws.com`) — reaching it from a private subnet
normally requires internet egress, typically via a NAT Gateway.

```
Private Instance → NAT Gateway → Internet Gateway → Internet → S3
                     (costs ~$32+/month, adds a hop)
```

## What a Gateway Endpoint Actually Does

A **Gateway** VPC Endpoint (available only for S3 and DynamoDB) works
differently from an **Interface** endpoint (which uses an ENI with a
private IP). Instead, it adds a special route to the route tables it is
associated with:

```
Destination: pl-xxxxxxxx (the "S3 prefix list" — all S3 IP ranges)
Target:      vpce-xxxxxxxx (this Gateway Endpoint)
```

When the instance makes a request to an S3 IP address, the route table
matches it against this prefix list and routes it directly to the
endpoint — which resolves the request via AWS's internal network,
never touching the public internet.

```
Private Instance → S3 Gateway Endpoint → Amazon S3
        (all within the AWS backbone network — no NAT, no IGW)
```

## Requirements

1. The endpoint must be created in the same VPC as the instance
2. The endpoint must be **associated with the route table** used by the
   subnet the instance is in (a common misconfiguration — see the S3
   Labs Lab 09 in this author's other repositories for exactly this bug)
3. The instance's IAM role must still have the appropriate S3 permissions
   — the endpoint provides network connectivity, not authorization

## Gateway Endpoint vs NAT Gateway for S3 Access

| | Gateway VPC Endpoint | NAT Gateway |
|---|---|---|
| Cost | Free | ~$0.045/hour + data processing |
| Scope | S3 and DynamoDB only | Any internet-bound traffic |
| Security | Traffic never leaves AWS network | Traffic technically leaves the VPC boundary |
| Setup complexity | Single resource + route table association | EIP + NAT Gateway + route table entry |

For workloads that only need S3 (or DynamoDB) access from a private
subnet, a Gateway Endpoint is strictly better — free, simpler, and more
secure — than provisioning a NAT Gateway.
