project_name = "aws-infra-demo"
environment  = "staging"
aws_region   = "us-east-1"

# Network Configuration
vpc_cidr = "10.0.0.0/16"
availability_zones = [
  "us-east-1a",
  "us-east-1b"
]
public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]
private_subnet_cidrs = [
  "10.0.10.0/24",
  "10.0.20.0/24"
]

# Compute Configuration
instance_type      = "t3.micro"
min_size          = 1
max_size          = 2
desired_capacity  = 1