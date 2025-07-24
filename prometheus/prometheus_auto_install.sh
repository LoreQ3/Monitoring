#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Variables
PROMETHEUS_VERSION="3.5.0"
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
SERVICE_FILE="/etc/systemd/system/prometheus.service"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

# Create Prometheus user if not exists
if ! id -u prometheus >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false prometheus
fi

# Download and extract Prometheus
echo "Downloading Prometheus ${PROMETHEUS_VERSION}..."
wget -q "$PROMETHEUS_URL" -O prometheus.tar.gz
tar xf prometheus.tar.gz
cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64" || exit 1

# Install binaries
echo "Installing Prometheus to ${INSTALL_DIR}..."
mv prometheus promtool "$INSTALL_DIR"
chown prometheus:prometheus "$INSTALL_DIR"/prometheus "$INSTALL_DIR"/promtool

# Create directories
mkdir -p "$CONFIG_DIR" "$DATA_DIR"
chown -R prometheus:prometheus "$CONFIG_DIR" "$DATA_DIR"

# Create systemd service file
echo "Creating systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prometheus Service
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=${INSTALL_DIR}/prometheus \
--config.file ${CONFIG_DIR}/prometheus.yml \
--storage.tsdb.path ${DATA_DIR} \
--web.console.templates=${CONFIG_DIR}/consoles \
--web.console.libraries=${CONFIG_DIR}/console_libraries
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Ensure config exists
if [ ! -f "/etc/prometheus/prometheus.yml" ]; then
    mkdir -p /etc/prometheus
    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF
    chown -R prometheus:prometheus /etc/prometheus
fi

# Ensure directories exist
mkdir -p /var/lib/prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries
chown -R prometheus:prometheus /var/lib/prometheus

# Reload systemd and enable service
echo "Enabling Prometheus service..."
systemctl daemon-reload
systemctl unmask prometheus.service 2>/dev/null || true
systemctl enable --now prometheus.service

# Verify service status
if systemctl is-active --quiet prometheus.service; then
    echo "Prometheus is running successfully!"
else
    echo "Error: Prometheus failed to start. Check logs with 'journalctl -u prometheus.service'."
    exit 1
fi

# Cleanup
cd ..
rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64" prometheus.tar.gz

echo "Installation complete. Prometheus is now running."
