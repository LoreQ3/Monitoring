#!/bin/bash

# user_sessions_exporter.sh
# Экспортер количества активных пользовательских сессий для Prometheus

# Порт для прослушивания (по умолчанию 9200)
PORT=${PORT:-9101}
HOST=${HOST:-0.0.0.0}

# Функция для получения метрик
get_metrics() {
    # Используем команду `who` для подсчета уникальных пользовательских сессий
    count=$(who | awk '{print $1}' | sort -u | wc -l)
    
    # Создаем метрику в формате Prometheus
    cat << EOF
# HELP node_active_users_count Number of active user sessions
# TYPE node_active_users_count gauge
node_active_users_count $count
EOF
}

# Функция для запуска HTTP сервера
start_server() {
    echo "Starting user sessions exporter on ${HOST}:${PORT}"
    while true; do
        # Используем netcat для простого HTTP сервера
        echo -e "HTTP/1.1 200 OK\nContent-Type: text/plain; version=0.0.4\n\n$(get_metrics)" | \
        nc -l -p ${PORT} -q 1
    done
}

# Проверяем аргументы командной строки
case "$1" in
    --help|-h)
        echo "Usage: $0 [--port PORT] [--host HOST]"
        echo "Export active user sessions metrics for Prometheus"
        exit 0
        ;;
    --port)
        PORT="$2"
        shift 2
        ;;
    --host)
        HOST="$2"
        shift 2
        ;;
esac

# Запускаем сервер
start_server
