#!/bin/bash

# Update system
yum update -y

# Install required packages
yum install -y docker git aws-cli

# Install Node.js 18
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

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

# Create systemd service for the application
cat > /etc/systemd/system/app.service << EOF
[Unit]
Description=Node.js Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/app
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=${environment}
Environment=PROJECT_NAME=${project_name}
Environment=AWS_REGION=us-east-1

[Install]
WantedBy=multi-user.target
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
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/${project_name}/${environment}/application",
            "log_stream_name": "{instance_id}/application.log"
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
if [ -z "$DEPLOYMENT_PACKAGE" ]; then
  echo "Usage: $0 <deployment-package-url>"
  exit 1
fi

# Stop the application
systemctl stop app

# Backup current deployment
if [ -d "/opt/app/src" ]; then
  mv /opt/app /opt/app.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create new app directory
mkdir -p /opt/app
cd /opt/app

# Download and extract deployment package
aws s3 cp "$DEPLOYMENT_PACKAGE" deployment.tar.gz
tar -xzf deployment.tar.gz
rm deployment.tar.gz

# Install dependencies
npm ci --production

# Set permissions
chown -R ec2-user:ec2-user /opt/app

# Start the application
systemctl start app
systemctl enable app

# Verify deployment
sleep 10
if systemctl is-active --quiet app; then
  echo "Deployment successful"
  # Clean up old backup (keep only last 3)
  ls -dt /opt/app.backup.* | tail -n +4 | xargs rm -rf
else
  echo "Deployment failed, rolling back"
  systemctl stop app
  if [ -d "/opt/app.backup.$(ls -t /opt/app.backup.* | head -1 | cut -d'.' -f3)" ]; then
    rm -rf /opt/app
    mv "$(ls -dt /opt/app.backup.* | head -1)" /opt/app
    systemctl start app
  fi
  exit 1
fi
EOF

chmod +x /opt/deploy.sh

# Signal that the instance is ready
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} || true

# Log completion
echo "User data script completed at $(date)" >> /var/log/user-data.log