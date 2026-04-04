#!/bin/bash
set -e

echo "==> Getting infrastructure endpoints..."

# Get actual endpoints from Terraform
DB_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "ENDPOINT_NOT_FOUND")
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint 2>/dev/null || echo "ENDPOINT_NOT_FOUND")

echo "Database: $DB_ENDPOINT"
echo "Redis: $REDIS_ENDPOINT"

# Create Flask app
cat > /tmp/app.py <<'EOF'
from flask import Flask, jsonify
import time

app = Flask(__name__)

@app.route('/health/health')
def health():
    return jsonify({"status": "healthy", "timestamp": time.time()})

@app.route('/health/ready')
def ready():
    return jsonify({"status": "ready"})

@app.route('/health/live')
def live():
    return jsonify({"status": "alive"})

@app.route('/metrics')
def metrics():
    return "# ServiceHub metrics\nservicehub_health 1.0\n"

@app.route('/')
def index():
    return jsonify({"service": "ServiceHub", "status": "running"})
EOF

# Create systemd service
cat > /tmp/servicehub.service <<EOFSVC
[Unit]
Description=ServiceHub Application
After=network.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=/opt/servicehub
Environment="FLASK_ENV=production"
Environment="DATABASE_URL=postgresql://servicehub_admin:SecurePassword123!@${DB_ENDPOINT}/servicehub"
Environment="REDIS_URL=redis://${REDIS_ENDPOINT}:6379/0"
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOFSVC

echo ""
echo "Files created in /tmp/"
echo "Now copy to instance via SSM..."

