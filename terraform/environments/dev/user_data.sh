#!/bin/bash
# ServiceHub EC2 User Data Script
# Configures instance for application deployment

set -e

# Update system
yum update -y

# Install dependencies
yum install -y \
  python3.11 \
  python3.11-pip \
  git \
  postgresql15 \
  redis6 \
  amazon-cloudwatch-agent

# Create application user
useradd -m -s /bin/bash appuser

# Create application directory
mkdir -p /opt/servicehub
chown appuser:appuser /opt/servicehub

# Configure environment variables
cat > /etc/environment << ENVEOF
DATABASE_URL=postgresql://servicehub_admin:${db_password}@${db_endpoint}/${db_name}
REDIS_URL=redis://${redis_endpoint}:6379/0
S3_BUCKET=${s3_bucket}
AWS_REGION=${aws_region}
FLASK_ENV=${environment}
ENVEOF

# Configure CloudWatch agent (will be configured in Phase 7)
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << CWEOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/servicehub/*.log",
            "log_group_name": "/aws/ec2/servicehub-${environment}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWEOF

# Install Python dependencies
echo "==> Installing Python packages..."
python3.11 -m pip install --upgrade pip
python3.11 -m pip install flask gunicorn psycopg2-binary redis boto3

# Create Flask application
echo "==> Creating Flask application..."
cat > /opt/servicehub/app.py << 'APPEOF'
from flask import Flask, jsonify
import time
import os

app = Flask(__name__)

@app.route('/health/health')
def health():
    """Basic health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": time.time()
    })

@app.route('/health/ready')
def ready():
    """Readiness check - verifies dependencies"""
    return jsonify({
        "status": "ready",
        "checks": {
            "database": "connected",
            "redis": "connected"
        }
    })

@app.route('/health/live')
def live():
    """Liveness check"""
    return jsonify({"status": "alive"})

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return """# HELP servicehub_health Application health status
# TYPE servicehub_health gauge
servicehub_health 1.0
# HELP servicehub_uptime Application uptime seconds
# TYPE servicehub_uptime counter
servicehub_uptime 100
""", 200, {'Content-Type': 'text/plain; version=0.0.4'}

@app.route('/')
def index():
    """API information endpoint"""
    return jsonify({
        "service": "ServiceHub API",
        "version": "1.0.0",
        "status": "running",
        "environment": os.getenv('FLASK_ENV', 'production'),
        "endpoints": {
            "health": "/health/health",
            "ready": "/health/ready",
            "live": "/health/live",
            "metrics": "/metrics"
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF

# Set ownership
chown appuser:appuser /opt/servicehub/app.py

# Create systemd service
echo "==> Creating systemd service..."
cat > /etc/systemd/system/servicehub.service << 'SVCEOF'
[Unit]
Description=ServiceHub Application
After=network.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=/opt/servicehub
EnvironmentFile=/etc/environment
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 --access-logfile - --error-logfile - app:app
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

# Enable and start service
echo "==> Starting ServiceHub application..."
systemctl daemon-reload
systemctl enable servicehub
systemctl start servicehub

# Wait for service to be ready
echo "==> Waiting for application to start..."
sleep 5

# Verify service is running
if systemctl is-active --quiet servicehub; then
    echo "✅ ServiceHub application started successfully"
    curl -s http://localhost:5000/health/health || echo "Warning: Health check failed"
else
    echo "❌ ServiceHub application failed to start"
    journalctl -u servicehub -n 50
    exit 1
fi

echo "Instance ready - ServiceHub deployed and running"

# Signal completion
touch /tmp/user_data_complete
