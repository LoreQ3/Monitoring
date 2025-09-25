#!/bin/bash

# Абсолютный путь к директории на ВАШЕМ СЕРВЕРЕ
METRICS_DIR="/home/ilya/Monitoring/Monitoring/prometheus/monitoring-stack/custom-metrics"
METRICS_FILE="$METRICS_DIR/session_metrics.prom"

# Создаем директорию, если ее нет
mkdir -p "$METRICS_DIR"

# Получаем метрики
SSH_SESSIONS=$(who | grep -c "pts/")
ACTIVE_USERS=$(who | awk '{print $1}' | sort -u | wc -l)
TOTAL_SESSIONS=$(who | wc -l)

# Создаем временный файл сначала
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF
# HELP user_ssh_sessions_total Total number of SSH sessions
# TYPE user_ssh_sessions_total gauge
user_ssh_sessions_total $SSH_SESSIONS

# HELP user_active_users_total Total number of active users
# TYPE user_active_users_total gauge
user_active_users_total $ACTIVE_USERS

# HELP user_total_sessions_total Total number of all sessions
# TYPE user_total_sessions_total gauge
user_total_sessions_total $TOTAL_SESSIONS

# HELP user_metrics_collector_success Whether metrics collection was successful
# TYPE user_metrics_collector_success gauge
user_metrics_collector_success 1
EOF

# Атомарно перемещаем временный файл в конечный
mv "$TEMP_FILE" "$METRICS_FILE"

# Устанавливаем правильные права
chmod 644 "$METRICS_FILE"

echo "Metrics saved to: $METRICS_FILE"
