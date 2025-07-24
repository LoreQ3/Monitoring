#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Variables
ZBXAGENT_URL="https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_6.0+debian11_all.deb"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

# Disable problematic repository temporarily
sed -i '/bullseye-backports/d' /etc/apt/sources.list

# Download and install Zabbix repository
echo "Downloading Zabbix Agent"
wget -q "$ZBXAGENT_URL" -O /tmp/zabbix-release.deb
dpkg -i /tmp/zabbix-release.deb

# Update package lists ignoring errors
apt update || true

# Install Zabbix Agent
apt install -y zabbix-agent

# Reload systemd and enable services
echo "Enabling services..."
systemctl daemon-reload
systemctl unmask zabbix-agent.service 2>/dev/null || true
systemctl restart zabbix-agent.service
systemctl enable --now zabbix-agent.service

# Verify service status
if systemctl is-active --quiet zabbix-agent.service; then
    echo "Zabbix Agent is running successfully!"
else
    echo "Error: Zabbix Agent failed to start. Check logs with:"
    echo "journalctl -u zabbix-agent.service -xe --no-pager"
    exit 1
fi

# Cleanup
rm -f /tmp/zabbix-release.deb

echo "Installation complete. Zabbix Agent is now running."
