#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Variables
ALERTMANAGER_VERSION="0.27.0"
ALERTMANAGER_URL="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/alertmanager"
SERVICE_FILE="/etc/systemd/system/alertmanager.service"
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
ALERT_RULES_DIR="/etc/prometheus/alerts"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

# Create alertmanager user if not exists
if ! id -u alertmanager >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false alertmanager
fi

# Create directories
mkdir -p "$CONFIG_DIR" "$ALERT_RULES_DIR"
chown alertmanager:alertmanager "$CONFIG_DIR"
chown prometheus:prometheus "$ALERT_RULES_DIR"

# Download and extract Alertmanager
echo "Downloading Alertmanager ${ALERTMANAGER_VERSION}..."
wget -q "$ALERTMANAGER_URL" -O alertmanager.tar.gz
tar xf alertmanager.tar.gz
cd "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64" || exit 1

# Install binaries
echo "Installing Alertmanager to ${INSTALL_DIR}..."
mv alertmanager amtool "$INSTALL_DIR"
chown alertmanager:alertmanager "$INSTALL_DIR"/alertmanager "$INSTALL_DIR"/amtool
chmod +x "$INSTALL_DIR"/alertmanager "$INSTALL_DIR"/amtool

# Create Alertmanager config with email alerts
echo "Creating Alertmanager configuration..."
cat > "$CONFIG_DIR"/config.yml <<'EOF'
global:
  resolve_timeout: 5m
  smtp_from: 'alertmanager@yourdomain.com'
  smtp_smarthost: 'smtp.yourmailserver.com:587'
  smtp_auth_username: 'your_email@domain.com'
  smtp_auth_password: 'your_email_password'
  smtp_require_tls: true

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: 'alerts@yourdomain.com'
    send_resolved: true
    headers:
      Subject: '{{ template "email.default.subject" . }}'
    html: '{{ template "email.default.html" . }}'

templates:
- '/etc/alertmanager/templates/*.tmpl'
EOF

# Create email template
mkdir -p "$CONFIG_DIR"/templates
cat > "$CONFIG_DIR"/templates/email.tmpl <<'EOF'
{{ define "email.default.subject" }}[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}{{ end }}

{{ define "email.default.html" }}
<h2>{{ .CommonLabels.alertname }}</h2>
<p><strong>Status:</strong> {{ .Status | toUpper }}</p>
<p><strong>Description:</strong> {{ .CommonAnnotations.description }}</p>
<p><strong>Details:</strong></p>
<ul>
{{ range .Alerts }}
  <li>
    <strong>Instance:</strong> {{ .Labels.instance }}<br>
    <strong>Started:</strong> {{ .StartsAt }}<br>
    {{ if gt (len .Annotations) 0 }}
    <strong>Annotations:</strong><br>
    <ul>
      {{ range $key, $value := .Annotations }}
      <li>{{ $key }}: {{ $value }}</li>
      {{ end }}
    </ul>
    {{ end }}
  </li>
{{ end }}
</ul>
{{ end }}
EOF

# Create host down alert rule
echo "Creating host down alert rule..."
cat > "$ALERT_RULES_DIR"/host_down.yml <<'EOF'
groups:
- name: host.rules
  rules:
  - alert: InstanceDown
    expr: up == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      description: '{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes'
      summary: 'Instance {{ $labels.instance }} down'
EOF

# Configure Prometheus
echo "Configuring Prometheus..."
cat > "$PROMETHEUS_CONFIG" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['localhost:9093']

rule_files:
  - '/etc/prometheus/alerts/*.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

# Set proper permissions
chown prometheus:prometheus "$PROMETHEUS_CONFIG"
chmod 644 "$PROMETHEUS_CONFIG"

# Create systemd service
echo "Creating systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Alertmanager Service
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=$INSTALL_DIR/alertmanager \\
--config.file=$CONFIG_DIR/config.yml \\
--storage.path=/var/lib/alertmanager

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Create data directory
mkdir -p /var/lib/alertmanager
chown alertmanager:alertmanager /var/lib/alertmanager

# Reload systemd and start services
echo "Starting services..."
systemctl daemon-reload
systemctl enable --now alertmanager.service

if systemctl is-active --quiet prometheus.service; then
    systemctl restart prometheus.service
fi

# Verify installation
if systemctl is-active --quiet alertmanager.service; then
    echo -e "\nAlertmanager installed successfully!"
    echo -e "Web interface: http://$(hostname -I | awk '{print $1}'):9093"
    echo -e "Email alerts configured for: alerts@yourdomain.com"
    echo -e "Host down alert rule added"
else
    echo "Error: Alertmanager failed to start. Check logs:"
    journalctl -u alertmanager.service -xe --no-pager
    exit 1
fi

# Cleanup
cd ..
rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64" alertmanager.tar.gz

echo "Installation complete. Alertmanager is now running with email notifications."
