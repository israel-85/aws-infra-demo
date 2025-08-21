project_name = "aws-infra-demo"
environment  = "production"
aws_region   = "us-east-1"

# Network Configuration
vpc_cidr = "10.1.0.0/16"
availability_zones = [
  "us-east-1a",
  "us-east-1b"
]
public_subnet_cidrs = [
  "10.1.1.0/24",
  "10.1.2.0/24"
]
private_subnet_cidrs = [
  "10.1.10.0/24",
  "10.1.20.0/24"
]

# Compute Configuration
instance_type      = "t3.small"
min_size          = 2
max_size          = 6
desired_capacity  = 2