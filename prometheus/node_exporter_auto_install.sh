#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Variables
NODE_EXPORTER_VERSION="1.9.1"
NODE_EXPORTER_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/prometheus/node-exporter"
SERVICE_FILE="/etc/systemd/system/node-exporter.service"
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

# Create Prometheus user if not exists
if ! id -u prometheus >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false prometheus
fi

# Create installation directory
mkdir -p "$CONFIG_DIR"
chown prometheus:prometheus "$CONFIG_DIR"

# Download and extract Node Exporter
echo "Downloading Node Exporter ${NODE_EXPORTER_VERSION}..."
wget -q "$NODE_EXPORTER_URL" -O node_exporter.tar.gz
tar xf node_exporter.tar.gz
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" || exit 1

# Install binary
echo "Installing Node Exporter to ${INSTALL_DIR}..."
mv node_exporter "$INSTALL_DIR"
chown prometheus:prometheus "$INSTALL_DIR"/node_exporter
chmod +x "$INSTALL_DIR"/node_exporter

# Create systemd service file
echo "Creating systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Node Exporter Service
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=${INSTALL_DIR}/node_exporter \
--web.listen-address=:9100 \
--collector.systemd \
--collector.processes

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Configure Prometheus to scrape Node Exporter
echo "Configuring Prometheus to scrape Node Exporter..."
if [ -f "$PROMETHEUS_CONFIG" ]; then
    # Check if config already exists
    if ! grep -q "job_name: 'node_exporter'" "$PROMETHEUS_CONFIG"; then
        # Add node_exporter config section
        sed -i "/scrape_configs:/a \  - job_name: 'node_exporter'\n    static_configs:\n      - targets: ['localhost:9100']" "$PROMETHEUS_CONFIG"
        echo "Added Node Exporter target to Prometheus config"
    else
        echo "Node Exporter target already exists in Prometheus config"
    fi
else
    # Create basic Prometheus config if not exists
    mkdir -p /etc/prometheus
    cat > "$PROMETHEUS_CONFIG" <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
    echo "Created new Prometheus config with Node Exporter target"
fi

# Set proper permissions
chown -R prometheus:prometheus /etc/prometheus
chmod 644 "$PROMETHEUS_CONFIG"

# Reload systemd and enable services
echo "Enabling services..."
systemctl daemon-reload
systemctl unmask node-exporter.service 2>/dev/null || true
systemctl enable --now node-exporter.service

# Restart Prometheus if running to apply config changes
if systemctl is-active --quiet prometheus.service; then
    systemctl restart prometheus.service
fi

# Verify service status
if systemctl is-active --quiet node-exporter.service; then
    echo "Node Exporter is running successfully!"
    echo "Access metrics at: http://$(hostname -I | awk '{print $1}'):9100/metrics"
else
    echo "Error: Node Exporter failed to start. Check logs with:"
    echo "journalctl -u node-exporter.service -xe --no-pager"
    exit 1
fi

# Cleanup
cd ..
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" node_exporter.tar.gz

echo "Installation complete. Node Exporter is now running and configured in Prometheus."
