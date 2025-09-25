#!/bin/bash

# Конфигурация
BACKUP_DIR="/opt/backup/prometheus"
DOCKER_COMPOSE_PATH="/home/ilya//Monitoring/Monitoring/monitoring-stack/docker-compose.yml"

# Функция выбора бэкапа
select_backup() {
    local backups=($(find "$BACKUP_DIR" -name "prometheus-backup-*.tar.gz" -type f | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo "Бэкапы не найдены в $BACKUP_DIR"
        exit 1
    fi
    
    echo "Доступные бэкапы:"
    for i in "${!backups[@]}"; do
        echo "$((i+1)). ${backups[$i]##*/}"
    done
    
    read -p "Выберите бэкап для восстановления (1-${#backups[@]}): " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo "Неверный выбор"
        exit 1
    fi
    
    echo "${backups[$((choice-1))]}"
}

# Восстановление
restore_backup() {
    local backup_file="$1"
    
    echo "Восстанавливаю из $backup_file"
    
    # Останавливаем Prometheus
    cd "$(dirname "$DOCKER_COMPOSE_PATH")"
    docker-compose stop prometheus
    
    # Восстанавливаем данные
    docker run --rm \
        -v prometheus_data:/target \
        -v "$BACKUP_DIR:/backup" \
        alpine \
        sh -c "rm -rf /target/* && tar xzf /backup/$(basename "$backup_file") -C /target"
    
    # Запускаем Prometheus
    docker-compose start prometheus
    
    echo "Восстановление завершено"
}

# Основная функция
main() {
    local backup_file=$(select_backup)
    
    if [ -z "$backup_file" ]; then
        exit 1
    fi
    
    read -p "Вы уверены, что хотите восстановить данные из $backup_file? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Отмена восстановления"
        exit 0
    fi
    
    restore_backup "$backup_file"
}

main
