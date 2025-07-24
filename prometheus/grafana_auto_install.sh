#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Variables
GRAFANA_VERSION="11.1.0"
GRAFANA_DEB_URL="https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb"
SERVICE_FILE="/usr/lib/systemd/system/grafana-server.service"  # Правильный путь для systemd
CONFIG_FILE="/etc/grafana/grafana.ini"

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

# Установка зависимостей (включая musl)
echo "Installing dependencies..."
apt-get update
apt-get install -y adduser libfontconfig1 musl

# Загрузка и установка Grafana
echo "Installing Grafana ${GRAFANA_VERSION}..."
wget -q "$GRAFANA_DEB_URL" -O grafana.deb
apt-get install -y ./grafana.deb  # Используем apt вместо dpkg для автоматического разрешения зависимостей
rm grafana.deb

# Настройка сервиса
echo "Configuring Grafana service..."
systemctl daemon-reload
systemctl enable --now grafana-server.service

# Проверка статуса
sleep 5  # Даем время для инициализации
if systemctl is-active --quiet grafana-server.service; then
    echo -e "\nGrafana successfully installed!"
    echo -e "Access: http://$(hostname -I | awk '{print $1}'):3000"
    echo -e "Default credentials: admin/admin\n"
else
    echo "Error: Grafana failed to start. Check logs:"
    journalctl -u grafana-server.service -xe --no-pager
    exit 1
fi
