#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SNMP_EXPORTER_VERSION="0.27.0"
SNMP_EXPORTER_PORT="9116"
CONFIG_DIR="/etc/snmp_exporter"
SERVICE_USER="snmp_exporter"

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
}

install_dependencies() {
    print_status "Installing dependencies..."
    apt-get update
    apt-get install -y wget tar snmp snmpd
}

download_snmp_exporter() {
    print_status "Downloading SNMP Exporter v${SNMP_EXPORTER_VERSION}..."
    local download_url="https://github.com/prometheus/snmp_exporter/releases/download/v${SNMP_EXPORTER_VERSION}/snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    if ! wget -q "$download_url" -O /tmp/snmp_exporter.tar.gz; then
        print_error "Failed to download SNMP Exporter"
        exit 1
    fi
}

extract_and_install() {
    print_status "Extracting and installing SNMP Exporter..."
    
    tar xzf /tmp/snmp_exporter.tar.gz -C /tmp/
    
    # Move binary
    mv /tmp/snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64/snmp_exporter /usr/local/bin/
    chmod +x /usr/local/bin/snmp_exporter
    
    # Create config directory
    mkdir -p ${CONFIG_DIR}
    
    # Move config file
    if [ -f "/tmp/snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64/snmp.yml" ]; then
        mv /tmp/snmp_exporter-${SNMP_EXPORTER_VERSION}.linux-amd64/snmp.yml ${CONFIG_DIR}/
    else
        print_warning "snmp.yml not found in archive, creating default config..."
        create_default_config
    fi
    
    # Cleanup
    rm -rf /tmp/snmp_exporter*
}

create_default_config() {
    cat > ${CONFIG_DIR}/snmp.yml << 'EOF'
default:
  version: 2
  auth:
    community: public
  walk:
    - 1.3.6.1.2.1.1
    - 1.3.6.1.2.1.2
    - 1.3.6.1.2.1.31
  metrics:
    - name: sysUpTime
      oid: 1.3.6.1.2.1.1.3
      type: gauge
      help: The time (in hundredths of a second) since the network management portion of the system was last re-initialized - 1.3.6.1.2.1.1.3
    - name: ifOperStatus
      oid: 1.3.6.1.2.1.2.2.1.8
      type: gauge
      help: The current operational state of the interface - 1.3.6.1.2.1.2.2.1.8
      indexes:
        - label: ifIndex
          oid: 1.3.6.1.2.1.2.2.1.1

if_mib:
  walk:
    - 1.3.6.1.2.1.2
    - 1.3.6.1.2.1.31
  metrics:
    - name: ifInOctets
      oid: 1.3.6.1.2.1.2.2.1.10
      type: counter
      help: The total number of octets received on the interface - 1.3.6.1.2.1.2.2.1.10
      indexes:
        - label: ifIndex
          oid: 1.3.6.1.2.1.2.2.1.1
    - name: ifOutOctets
      oid: 1.3.6.1.2.1.2.2.1.16
      type: counter
      help: The total number of octets transmitted out of the interface - 1.3.6.1.2.1.2.2.1.16
      indexes:
        - label: ifIndex
          oid: 1.3.6.1.2.1.2.2.1.1
EOF
}

create_service_user() {
    print_status "Creating service user ${SERVICE_USER}..."
    if ! id "${SERVICE_USER}" &>/dev/null; then
        useradd --no-create-home --shell /bin/false ${SERVICE_USER}
    fi
    
    chown -R ${SERVICE_USER}:${SERVICE_USER} ${CONFIG_DIR}
    chown ${SERVICE_USER}:${SERVICE_USER} /usr/local/bin/snmp_exporter
}

create_systemd_service() {
    print_status "Creating systemd service..."
    
    cat > /etc/systemd/system/snmp_exporter.service << EOF
[Unit]
Description=SNMP Exporter
After=network.target
Wants=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
Type=simple
ExecStart=/usr/local/bin/snmp_exporter \\
  --config.file=${CONFIG_DIR}/snmp.yml \\
  --web.listen-address=:${SNMP_EXPORTER_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

setup_local_snmp() {
    print_status "Setting up local SNMP daemon..."
    
    # Backup existing config
    if [ -f "/etc/snmp/snmpd.conf" ]; then
        cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup
    fi
    
    # Create basic SNMP config
    cat > /etc/snmp/snmpd.conf << 'EOF'
rocommunity public 127.0.0.1
rocommunity public 192.168.0.0/16
rocommunity public 10.0.0.0/8
sysLocation "Server Room"
sysContact "Admin <admin@example.com>"
sysName $(hostname)
EOF
    
    systemctl enable snmpd
    systemctl restart snmpd
}

configure_firewall() {
    print_status "Configuring firewall..."
    
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow ${SNMP_EXPORTER_PORT}/tcp
        ufw allow 161/udp
        print_status "Firewall rules added"
    fi
}

configure_prometheus() {
    print_status "Configuring Prometheus..."
    
    local prometheus_config="/etc/prometheus/prometheus.yml"
    
    if [ -f "$prometheus_config" ]; then
        if ! grep -q "snmp" "$prometheus_config"; then
            cat >> "$prometheus_config" << EOF

# SNMP monitoring
  - job_name: 'snmp'
    static_configs:
      - targets:
        - 192.168.13.1
        - 192.168.13.249
        - 127.0.0.1
    metrics_path: /snmp
    params:
      module: [if_mib]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:${SNMP_EXPORTER_PORT}
    scrape_interval: 30s
EOF
            
            # Reload Prometheus
            systemctl reload prometheus
        else
            print_warning "SNMP config already exists in Prometheus"
        fi
    else
        print_warning "Prometheus config not found, please add manually"
    fi
}

start_services() {
    print_status "Starting services..."
    
    systemctl daemon-reload
    systemctl enable snmp_exporter
    systemctl start snmp_exporter
    systemctl restart snmpd
    
    sleep 3
    
    systemctl status snmp_exporter --no-pager
    systemctl status snmpd --no-pager
}

test_installation() {
    print_status "Testing installation..."
    
    # Test SNMP exporter
    if curl -s http://localhost:${SNMP_EXPORTER_PORT}/metrics > /dev/null; then
        print_status "SNMP exporter is running"
    else
        print_error "SNMP exporter is not responding"
    fi
    
    # Test local SNMP
    if snmpwalk -v 2c -c public 127.0.0.1 system > /dev/null 2>&1; then
        print_status "Local SNMP is working"
    else
        print_error "Local SNMP is not working"
    fi
    
    # Test SNMP through exporter
    if curl -s "http://localhost:${SNMP_EXPORTER_PORT}/snmp?target=127.0.0.1&module=if_mib" > /dev/null; then
        print_status "SNMP exporter can query localhost"
    else
        print_error "SNMP exporter cannot query localhost"
    fi
}

show_summary() {
    echo ""
    echo -e "${GREEN}=== Installation Summary ==="
    echo "SNMP Exporter installed: /usr/local/bin/snmp_exporter"
    echo "Configuration directory: ${CONFIG_DIR}"
    echo "Service user: ${SERVICE_USER}"
    echo "Web interface: http://localhost:${SNMP_EXPORTER_PORT}"
    echo "Metrics endpoint: http://localhost:${SNMP_EXPORTER_PORT}/metrics"
    echo "SNMP query endpoint: http://localhost:${SNMP_EXPORTER_PORT}/snmp"
    echo ""
    echo "To test SNMP exporter:"
    echo "  curl http://localhost:${SNMP_EXPORTER_PORT}/metrics"
    echo "  curl 'http://localhost:${SNMP_EXPORTER_PORT}/snmp?target=127.0.0.1&module=if_mib'"
    echo ""
    echo "To monitor network devices, add them to Prometheus config:"
    echo "  /etc/prometheus/prometheus.yml"
    echo -e "===============================${NC}"
}

main() {
    print_status "Starting SNMP Exporter installation..."
    check_root
    install_dependencies
    download_snmp_exporter
    extract_and_install
    create_service_user
    create_systemd_service
    setup_local_snmp
    configure_firewall
    configure_prometheus
    start_services
    test_installation
    show_summary
}

# Run main function
main "$@"
