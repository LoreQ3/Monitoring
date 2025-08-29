#!/bin/bash
# install_custom_exporter.sh - Automated installation of custom user metrics exporter

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
EXPORTER_PORT="9101"
EXPORTER_SCRIPT="/usr/local/bin/custom_exporter.py"
SERVICE_FILE="/etc/systemd/system/custom_exporter.service"
SCRIPT_DIR="/tmp/custom_exporter"
USER_NAME="custom_exporter"

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
        print_error "Please run as root or with sudo"
        exit 1
    fi
}

install_dependencies() {
    print_status "Installing system dependencies..."
    
    # Update package list
    apt-get update -qq
    
    # Install required packages
    apt-get install -y -qq python3 python3-pip python3-venv curl whois
}

create_user() {
    print_status "Creating system user: $USER_NAME"
    
    if id "$USER_NAME" &>/dev/null; then
        print_warning "User $USER_NAME already exists"
    else
        useradd -rs /bin/false "$USER_NAME"
        print_status "User $USER_NAME created"
    fi
}

create_python_script() {
    print_status "Creating Python exporter script..."
    
    cat > "$EXPORTER_SCRIPT" << 'EOF'
#!/usr/bin/env python3

from prometheus_client import Gauge, start_http_server
import subprocess
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('user_exporter')

# Create metrics
USER_COUNT = Gauge('node_active_users_count', 'Number of active user sessions')
USER_COUNT_ERROR = Gauge('node_user_count_errors', 'Number of errors in user counting')

def get_user_count():
    try:
        # Method 1: Using 'who' command
        result = subprocess.run(
            ['who', '-q'],
            capture_output=True,
            text=True,
            timeout=10,
            check=True
        )
        
        if result.returncode == 0:
            users_line = result.stdout.strip().split('\n')[-1]
            if 'users=' in users_line:
                count = int(users_line.split('=')[1])
                logger.info(f"Found {count} active users using 'who' command")
                USER_COUNT_ERROR.set(0)
                return count
        
        # Fallback method: count unique users from 'who'
        result = subprocess.run(
            ['who'],
            capture_output=True,
            text=True,
            timeout=10,
            check=True
        )
        
        users = set()
        for line in result.stdout.split('\n'):
            if line.strip():
                user = line.split()[0]
                users.add(user)
        
        count = len(users)
        logger.info(f"Found {count} active users: {users}")
        USER_COUNT_ERROR.set(0)
        return count
        
    except subprocess.TimeoutExpired:
        logger.warning("Command timed out")
        USER_COUNT_ERROR.inc()
        return 0
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {e}")
        USER_COUNT_ERROR.inc()
        return 0
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        USER_COUNT_ERROR.inc()
        return 0

def main():
    try:
        logger.info(f"Starting Custom User Exporter on port {EXPORTER_PORT}")
        
        # Start HTTP server
        start_http_server(EXPORTER_PORT)
        logger.info("Exporter started successfully")
        
        # Main loop
        while True:
            count = get_user_count()
            USER_COUNT.set(count)
            time.sleep(30)
            
    except Exception as e:
        logger.error(f"Failed to start exporter: {e}")
        raise

if __name__ == '__main__':
    EXPORTER_PORT = 9101
    main()
EOF

    # Make script executable
    chmod 755 "$EXPORTER_SCRIPT"
    chown "$USER_NAME":"$USER_NAME" "$EXPORTER_SCRIPT"
    print_status "Python script created: $EXPORTER_SCRIPT"
}

install_python_dependencies() {
    print_status "Installing Python dependencies..."
    
    # Install prometheus-client system-wide
    pip3 install prometheus-client --quiet
    
    # Verify installation
    if python3 -c "import prometheus_client" &>/dev/null; then
        print_status "Python dependencies installed successfully"
    else
        print_error "Failed to install Python dependencies"
        exit 1
    fi
}

create_service_file() {
    print_status "Creating systemd service file..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Custom User Metrics Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
ExecStart=/usr/bin/python3 $EXPORTER_SCRIPT
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10s
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=custom_exporter
Environment=PYTHONUNBUFFERED=1

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF

    print_status "Service file created: $SERVICE_FILE"
}

setup_logging() {
    print_status "Setting up logging..."
    
    # Create log directory
    mkdir -p /var/log/custom_exporter
    chown "$USER_NAME":"$USER_NAME" /var/log/custom_exporter
    
    # Add logrotate configuration
    cat > /etc/logrotate.d/custom_exporter << EOF
/var/log/custom_exporter/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $USER_NAME $USER_NAME
}
EOF
}

enable_and_start_service() {
    print_status "Enabling and starting service..."
    
    systemctl daemon-reload
    systemctl enable custom_exporter.service
    systemctl start custom_exporter.service
    
    # Wait a bit for service to start
    sleep 2
    
    # Check service status
    if systemctl is-active --quiet custom_exporter.service; then
        print_status "Service is running successfully"
    else
        print_error "Service failed to start"
        journalctl -u custom_exporter.service -n 20 --no-pager
        exit 1
    fi
}

test_exporter() {
    print_status "Testing exporter..."
    
    # Wait a bit for metrics to be collected
    sleep 3
    
    # Test metrics endpoint
    if curl -s "http://localhost:$EXPORTER_PORT/metrics" | grep -q "node_active_users_count"; then
        print_status "Exporter is working correctly!"
        print_status "Metrics available at: http://localhost:$EXPORTER_PORT/metrics"
    else
        print_warning "Exporter started but metrics not found yet"
        print_status "Checking again in 10 seconds..."
        sleep 10
        if curl -s "http://localhost:$EXPORTER_PORT/metrics" | grep -q "node_active_users_count"; then
            print_status "Exporter is now working correctly!"
        else
            print_error "Exporter test failed"
            journalctl -u custom_exporter.service -n 20 --no-pager
        fi
    fi
}

setup_firewall() {
    print_status "Configuring firewall (if ufw is enabled)..."
    
    if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$EXPORTER_PORT"
        print_status "Firewall rule added for port $EXPORTER_PORT"
    fi
}


print_summary() {
    echo ""
    echo -e "${GREEN}=== Installation Summary ==="
    echo -e "✅ Custom exporter installed successfully!"
    echo -e "📊 Metrics endpoint: http://localhost:9101/metrics"
    echo -e "🔧 Service name: custom_exporter"
    echo -e "👤 Running as user: $USER_NAME"
    echo -e "📝 Logs: journalctl -u custom_exporter.service"
    echo -e "🔄 Control: systemctl status|start|stop|restart custom_exporter"
    echo -e "=============================${NC}"
    echo ""
    echo "Next steps:"
    echo "Add to Prometheus config:"
    echo "   - job_name: 'custom_exporter'"
    echo "     static_configs:"
    echo "       - targets: ['localhost:9101']"
    echo ""
}

main() {
    print_status "Starting Custom Exporter installation..."
    check_root
    
    # Execute installation steps
    install_dependencies
    create_user
    create_python_script
    install_python_dependencies
    create_service_file
    setup_logging
    enable_and_start_service
    test_exporter
    setup_firewall
    print_summary
    
    print_status "Installation completed successfully! 🎉"
}

# Run main function
main "$@"
