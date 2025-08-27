#!/bin/bash

# Update system
yum update -y

# Install required packages
yum install -y docker git aws-cli nginx

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Create application directory
mkdir -p /opt/app
chown ec2-user:ec2-user /opt/app

# Configure nginx
systemctl start nginx
systemctl enable nginx

# Create nginx environment configuration
cat > /etc/nginx/conf.d/environment.conf << EOF
# Set environment variable for nginx
map \$host \$environment {
    default "${environment}";
}
EOF

# Create log directory
mkdir -p /var/log/app
chown ec2-user:ec2-user /var/log/app

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/${project_name}/${environment}/nginx-access",
            "log_stream_name": "{instance_id}/nginx-access.log"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/${project_name}/${environment}/nginx-error",
            "log_stream_name": "{instance_id}/nginx-error.log"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/${project_name}/${environment}/system",
            "log_stream_name": "{instance_id}/messages"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

# Create deployment script
cat > /opt/deploy.sh << 'EOF'
#!/bin/bash

DEPLOYMENT_PACKAGE=$1
ENVIRONMENT=${2:-staging}

if [ -z "$DEPLOYMENT_PACKAGE" ]; then
  echo "Usage: $0 <deployment-package-url> [environment]"
  exit 1
fi

# Backup current deployment
if [ -d "/usr/share/nginx/html.backup" ]; then
  rm -rf /usr/share/nginx/html.backup
fi
if [ -d "/usr/share/nginx/html" ]; then
  cp -r /usr/share/nginx/html /usr/share/nginx/html.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create temporary directory for extraction
mkdir -p /tmp/deployment
cd /tmp/deployment

# Download and extract deployment package
aws s3 cp "$DEPLOYMENT_PACKAGE" deployment.tar.gz
tar -xzf deployment.tar.gz
rm deployment.tar.gz

# Process HTML with environment variables
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
ENV_CLASS=$ENVIRONMENT

# Replace placeholders in index.html
sed -e "s/__ENVIRONMENT__/$ENVIRONMENT/g" \
    -e "s/__ENVIRONMENT_CLASS__/$ENV_CLASS/g" \
    -e "s/__TIMESTAMP__/$TIMESTAMP/g" \
    index.html > /usr/share/nginx/html/index.html

# Copy nginx configuration
cp nginx.conf /etc/nginx/nginx.conf

# Set permissions
chown -R nginx:nginx /usr/share/nginx/html

# Test nginx configuration
nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx configuration test failed, rolling back"
  if [ -d "/usr/share/nginx/html.backup.$(ls -t /usr/share/nginx/html.backup.* | head -1 | cut -d'.' -f4)" ]; then
    rm -rf /usr/share/nginx/html
    cp -r "$(ls -dt /usr/share/nginx/html.backup.* | head -1)" /usr/share/nginx/html
  fi
  exit 1
fi

# Reload nginx
systemctl reload nginx

# Verify deployment
sleep 5
if curl -f http://localhost/health > /dev/null 2>&1; then
  echo "Deployment successful"
  # Clean up old backups (keep only last 3)
  ls -dt /usr/share/nginx/html.backup.* 2>/dev/null | tail -n +4 | xargs rm -rf 2>/dev/null
  rm -rf /tmp/deployment
else
  echo "Deployment failed, rolling back"
  if [ -d "/usr/share/nginx/html.backup.$(ls -t /usr/share/nginx/html.backup.* | head -1 | cut -d'.' -f4)" ]; then
    rm -rf /usr/share/nginx/html
    cp -r "$(ls -dt /usr/share/nginx/html.backup.* | head -1)" /usr/share/nginx/html
    systemctl reload nginx
  fi
  rm -rf /tmp/deployment
  exit 1
fi
EOF

chmod +x /opt/deploy.sh

# Signal that the instance is ready
/opt/aws/bin/cfn-signal -e $? --stack $${AWS::StackName} --resource AutoScalingGroup --region $${AWS::Region} || true

# Log completion
echo "User data script completed at $(date)" >> /var/log/user-data.log