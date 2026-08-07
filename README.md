# 🔒 Secure File Transfer to Amazon S3 from a Private EC2 Instance

[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com)

> A secure AWS reference architecture for transferring files from a **private** EC2 instance to an Amazon S3 bucket — **without exposing the instance to the public internet**, and without needing a NAT Gateway or Internet Gateway for S3 access.

---

## 🎯 What This Solves

Private EC2 instances (no public IP, no NAT Gateway) commonly need to
read or write files to S3 — application logs, backups, data exports,
configuration files. The default assumption is that this requires
internet egress via a NAT Gateway. It doesn't.

| Approach | Public Internet Exposure | NAT Gateway Required | Cost |
|---|---|---|---|
| Public EC2 + Internet Gateway | ❌ Yes — direct exposure | No | Free (IGW) |
| Private EC2 + NAT Gateway | ✅ None | Yes | ~$32+/month |
| **Private EC2 + S3 Gateway VPC Endpoint (this project)** | ✅ None | **No** | **Free** |

---

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────┐
│                          VPC                          │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │              Private Subnet (no IGW route)      │  │
│  │                                                 │  │
│  │   ┌───────────────────┐                         │  │
│  │   │   EC2 Instance    │                         │  │
│  │   │   • No public IP  │                         │  │
│  │   │   • IAM Role with │                         │  │
│  │   │     S3 permissions│                         │  │
│  │   └─────────┬─────────┘                         │  │
│  │             │ aws s3 cp file.txt s3://bucket/   │  │
│  │             ▼                                   │  │
│  │   ┌───────────────────────────────┐             │  │
│  │   │  Route Table entry:           │             │  │
│  │   │  pl-xxxxxxxx (S3 prefix list) │             │  │
│  │   │       → vpce-xxxxxxxx         │             │  │
│  │   └─────────┬─────────────────────┘             │  │
│  └─────────────┼───────────────────────────────────┘  │
│                │                                      │
│                ▼                                      │
│   ┌─────────────────────────────┐                     │
│   │  S3 Gateway VPC Endpoint    │  ← traffic never    │
│   │  (associated to private RT) │    leaves the AWS   │
│   └─────────────┬───────────────┘    network          │
└─────────────────┼─────────────────────────────────────┘
                  │
                  ▼
       ┌─────────────────────┐
       │   Amazon S3 Bucket  │
       └─────────────────────┘

❌ No Internet Gateway route for this subnet
❌ No NAT Gateway
✅ Traffic to S3 stays entirely within the AWS network
```

---

## 🔑 What Gets Created

| Resource | Purpose |
|---|---|
| **VPC + Private Subnet** | No route to an Internet Gateway — genuinely private |
| **S3 Gateway VPC Endpoint** | Injects a route for S3 traffic into the private route table |
| **IAM Role + Instance Profile** | Grants the EC2 instance scoped `s3:PutObject`/`s3:GetObject` permissions |
| **EC2 Instance (private, SSM-managed)** | No public IP, no SSH key — managed via Systems Manager Session Manager |
| **S3 Bucket** | Encrypted, versioned, fully private destination for transferred files |

---

## 📁 Project Structure

```
private-ec2-to-s3/
├── README.md
├── .gitignore
├── LICENSE
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── scripts/
│   └── test_transfer.sh          # End-to-end validation script
└── docs/
    ├── how-gateway-endpoints-work.md
    └── troubleshooting.md
```

---

## 🚀 Deployment

```bash
git clone https://github.com/e-mulenga/aws-private-ec2-to-s3.git
cd aws-private-ec2-to-s3/terraform

terraform init
terraform plan
terraform apply
```

### Verify the Transfer Works

```bash
# Connect to the private instance via SSM (no SSH key, no public IP needed)
aws ssm start-session --target $(terraform output -raw instance_id)

# Once connected — create and upload a test file
echo "Hello from a private instance" > test.txt
aws s3 cp test.txt s3://$(terraform output -raw bucket_name)/test.txt

# Confirm the upload
aws s3 ls s3://$(terraform output -raw bucket_name)/
```

Or run the included validation script from your local machine:

```bash
cd ../scripts
chmod +x test_transfer.sh
./test_transfer.sh
```

---

## 🔐 Security Highlights

| Control | Implementation |
|---|---|
| No public IP on the instance | `associate_public_ip_address = false` |
| No inbound internet exposure | No IGW route in the private route table |
| No NAT Gateway required | S3 Gateway VPC Endpoint handles S3 traffic entirely within AWS |
| Least privilege IAM | Instance role scoped to `s3:PutObject`/`s3:GetObject` on this bucket only |
| Encrypted S3 storage | Server-side encryption enabled by default |
| No SSH keys | Access via AWS Systems Manager Session Manager only |
| Full audit trail | All S3 API calls and Session Manager sessions logged via CloudTrail |

---

## 💰 Cost

| Resource | Monthly Cost |
|---|---|
| S3 Gateway VPC Endpoint | **Free** |
| EC2 t3.micro | ~$8.50 (or covered by Free Tier) |
| S3 storage | ~$0.023/GB |
| **NAT Gateway avoided** | **Saves ~$32+/month vs. the NAT Gateway alternative** |

---

## 🧹 Teardown

```bash
cd terraform
terraform destroy
```

---

## 👤 Author

**Emmanuel Mulenga** — Multi-Cloud Engineer
- 🌐 [![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=flat&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/emmanuel-mulenga)
- 💻 [![GitHub Profile](https://img.shields.io/badge/GitHub-e--mulenga-181717?style=flat&logo=github)](https://github.com/e-mulenga)