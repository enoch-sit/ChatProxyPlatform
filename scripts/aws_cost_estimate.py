"""
AWS Monthly Cost Estimate - chatproxy-dev (us-east-1)
Based on scanned resources, March 2026 pricing
"""

# ============================================================
# ECS FARGATE (5 services, 1 task each, always-on)
# us-east-1: $0.04048/vCPU-hr, $0.004445/GB-hr
# ============================================================
FARGATE_CPU_HR = 0.04048
FARGATE_MEM_GB_HR = 0.004445
HOURS = 730  # avg hours/month

services = [
    ("bridge",                  0.25, 0.5),
    ("flowise-proxy-service",   0.50, 1.0),
    ("accounting-service",      0.25, 0.5),
    ("auth-service",            0.25, 0.5),
    ("flowise-service",         0.50, 1.0),
]

print("=== ECS Fargate ===")
fargate_total = 0
for name, cpu, mem_gb in services:
    cpu_cost = cpu * FARGATE_CPU_HR * HOURS
    mem_cost = mem_gb * FARGATE_MEM_GB_HR * HOURS
    subtotal = cpu_cost + mem_cost
    fargate_total += subtotal
    print(f"  {name}: ${subtotal:.2f} (cpu=${cpu_cost:.2f} + mem=${mem_cost:.2f})")
print(f"  SUBTOTAL: ${fargate_total:.2f}")

# ============================================================
# PUBLIC IPv4 ADDRESSES  ($0.005/hr per address as of Feb 2024)
# ============================================================
# 4 EIPs (all attached: 1 for EC2, 3 others likely for old resources)
# 2 ALBs in 2 AZs each = 4 ALB node IPs (not EIPs, but still charged)
# 5 ECS tasks in public subnets = 5 task IPs
# Note: EC2 EIP is counted in the 4 EIPs
IPV4_HR = 0.005
eips = 4          # explicitly allocated EIPs
alb_ips = 4       # 2 ALBs × 2 AZs = 4 node IPs
ecs_task_ips = 5  # 5 tasks in public subnets
total_ips = eips + alb_ips + ecs_task_ips
ipv4_cost = total_ips * IPV4_HR * HOURS

print(f"\n=== Public IPv4 Addresses ({total_ips} total) ===")
print(f"  4 EIPs: ${4 * IPV4_HR * HOURS:.2f}")
print(f"  4 ALB node IPs (2 ALBs × 2 AZs): ${4 * IPV4_HR * HOURS:.2f}")
print(f"  5 ECS task IPs (public subnet): ${5 * IPV4_HR * HOURS:.2f}")
print(f"  SUBTOTAL: ${ipv4_cost:.2f}")

# ============================================================
# APPLICATION LOAD BALANCERS (2x)
# $0.0225/ALB-hr + LCU ($0.008/LCU-hr, ~1 LCU for dev traffic)
# ============================================================
ALB_HR = 0.0225
LCU_HR = 0.008
alb_fixed = 2 * ALB_HR * HOURS
alb_lcu = 2 * 1 * LCU_HR * HOURS  # ~1 LCU per ALB for low traffic
alb_total = alb_fixed + alb_lcu

print(f"\n=== Application Load Balancers (2x) ===")
print(f"  Fixed (2 × $0.0225/hr): ${alb_fixed:.2f}")
print(f"  LCU usage (~1 LCU each): ${alb_lcu:.2f}")
print(f"  SUBTOTAL: ${alb_total:.2f}")

# ============================================================
# RDS PostgreSQL - db.t4g.micro, 20GB, single-AZ
# $0.016/hr instance + $0.115/GB/month storage
# ============================================================
RDS_HR = 0.016
rds_instance = RDS_HR * HOURS
rds_storage = 20 * 0.115
rds_total = rds_instance + rds_storage

print(f"\n=== RDS PostgreSQL (db.t4g.micro, 20GB) ===")
print(f"  Instance ($0.016/hr): ${rds_instance:.2f}")
print(f"  Storage (20GB × $0.115): ${rds_storage:.2f}")
print(f"  SUBTOTAL: ${rds_total:.2f}")

# ============================================================
# EC2 - t4g.micro (MongoDB)
# On-demand: $0.0084/hr + 8GB EBS gp3 ($0.08/GB/month)
# ============================================================
EC2_HR = 0.0084
ec2_instance = EC2_HR * HOURS
ec2_ebs = 8 * 0.08
ec2_total = ec2_instance + ec2_ebs

print(f"\n=== EC2 t4g.micro (MongoDB) ===")
print(f"  Instance ($0.0084/hr): ${ec2_instance:.2f}")
print(f"  EBS gp3 8GB: ${ec2_ebs:.2f}")
print(f"  SUBTOTAL: ${ec2_total:.2f}")

# ============================================================
# SECRETS MANAGER
# $0.40/secret/month + $0.05 per 10k API calls
# ============================================================
secrets_cost = 8 * 0.40
print(f"\n=== Secrets Manager (8 secrets) ===")
print(f"  SUBTOTAL: ${secrets_cost:.2f}")

# ============================================================
# ROUTE53
# $0.50/hosted zone/month + $0.40 per million queries
# ============================================================
r53_cost = 1 * 0.50
print(f"\n=== Route53 (1 hosted zone) ===")
print(f"  SUBTOTAL: ${r53_cost:.2f}")

# ============================================================
# ECR (1.34 GB storage)
# $0.10/GB/month
# ============================================================
ecr_cost = 1.34 * 0.10
print(f"\n=== ECR (1.34 GB) ===")
print(f"  SUBTOTAL: ${ecr_cost:.2f}")

# ============================================================
# S3 (2 buckets, minimal data)
# $0.023/GB + request costs
# ============================================================
s3_cost = 0.50  # estimate for very small usage
print(f"\n=== S3 (2 buckets, minimal) ===")
print(f"  SUBTOTAL (estimated): ${s3_cost:.2f}")

# ============================================================
# DATA TRANSFER
# Free: inbound, first 100GB outbound to internet
# $0.01/GB inter-AZ
# Dev traffic: minimal
# ============================================================
data_transfer = 2.00  # conservative estimate
print(f"\n=== Data Transfer (low traffic) ===")
print(f"  SUBTOTAL (estimated): ${data_transfer:.2f}")

# ============================================================
# CLOUDWATCH LOGS
# $0.50/GB ingested, $0.03/GB stored, 5GB free/month
# ============================================================
cw_cost = 2.00  # estimate: several log groups, low volume
print(f"\n=== CloudWatch Logs ===")
print(f"  SUBTOTAL (estimated): ${cw_cost:.2f}")

# ============================================================
# TOTAL
# ============================================================
grand_total = (fargate_total + ipv4_cost + alb_total + rds_total +
               ec2_total + secrets_cost + r53_cost + ecr_cost +
               s3_cost + data_transfer + cw_cost)

print(f"\n{'='*50}")
print(f"  ESTIMATED MONTHLY TOTAL: ${grand_total:.2f}")
print(f"{'='*50}")
print()
print("NOTE: Estimates assume 1 task per service (no autoscaling),")
print("low dev traffic, and on-demand pricing (no savings plans).")
print("Actual bill may vary by ±10-20% based on traffic and usage.")
