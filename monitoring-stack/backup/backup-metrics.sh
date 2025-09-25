#!/bin/bash

# Конфигурация
BACKUP_DIR="/opt/backup/prometheus"
RETENTION_DAYS=30
DOCKER_COMPOSE_PATH="/home/ilya/Monitoring/Monitoring/monitoring-stack/docker-compose.yml"
LOG_FILE="/var/log/prometheus-backup.log"

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функция логирования
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() { log "${GREEN}INFO${NC}: $1"; }
log_warn() { log "${YELLOW}WARN${NC}: $1"; }
log_error() { log "${RED}ERROR${NC}: $1"; }

# Создание директории для бэкапов
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    if [ $? -ne 0 ]; then
        log_error "Не удалось создать директорию $BACKUP_DIR"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker не установлен"
        exit 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        log_error "Файл docker-compose.yml не найден: $DOCKER_COMPOSE_PATH"
        exit 1
    fi
}

# Получение команды docker compose
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Остановка Prometheus для консистентного бэкапа
stop_prometheus() {
    local compose_cmd=$(get_docker_compose_cmd)
    
    log_info "Останавливаю Prometheus для консистентного бэкапа..."
    
    cd "$(dirname "$DOCKER_COMPOSE_PATH")"
    $compose_cmd stop prometheus
    
    if [ $? -ne 0 ]; then
        log_warn "Не удалось остановить Prometheus, пробую продолжить..."
        return 1
    fi
    
    # Ждем завершения записи на диск
    sleep 10
    log_info "Prometheus остановлен"
    return 0
}

# Запуск Prometheus после бэкапа
start_prometheus() {
    local compose_cmd=$(get_docker_compose_cmd)
    
    log_info "Запускаю Prometheus..."
    
    cd "$(dirname "$DOCKER_COMPOSE_PATH")"
    
    # Используем up -d вместо start, так как контейнер мог быть удален при остановке
    $compose_cmd up -d prometheus
    
    if [ $? -ne 0 ]; then
        log_error "Не удалось запустить Prometheus"
        return 1
    fi
    
    # Ждем запуска
    sleep 10
    
    # Проверяем что контейнер запущен
    local container_status=$($compose_cmd ps prometheus | grep -c "Up")
    if [ "$container_status" -eq 1 ]; then
        log_info "Prometheus успешно запущен"
        return 0
    else
        log_error "Prometheus не запустился"
        return 1
    fi
}

# Создание бэкапа
create_backup() {
    local backup_file="$BACKUP_DIR/prometheus-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    log_info "Создаю бэкап в $backup_file"
    
    # Проверяем существование volume
    if ! docker volume inspect prometheus_data &> /dev/null; then
        log_error "Volume prometheus_data не существует"
        return 1
    fi
    
    # Создаем бэкап volume
    docker run --rm \
        -v prometheus_data:/source \
        -v "$BACKUP_DIR:/backup" \
        alpine \
        tar czf "/backup/$(basename $backup_file)" -C /source .
    
    if [ $? -ne 0 ]; then
        log_error "Ошибка при создании бэкапа"
        return 1
    fi
    
    # Проверяем размер бэкапа
    local backup_size=$(du -h "$backup_file" | cut -f1)
    log_info "Бэкап создан успешно. Размер: $backup_size"
    
    echo "$backup_file"
    return 0
}

# Очистка старых бэкапов
cleanup_old_backups() {
    log_info "Удаляю бэкапы старше $RETENTION_DAYS дней..."
    
    find "$BACKUP_DIR" -name "prometheus-backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
    
    local remaining_backups=$(find "$BACKUP_DIR" -name "prometheus-backup-*.tar.gz" -type f | wc -l)
    log_info "Текущее количество бэкапов: $remaining_backups"
}

# Проверка целостности бэкапа
verify_backup() {
    local backup_file="$1"
    
    log_info "Проверяю целостность бэкапа..."
    
    if [ ! -f "$backup_file" ]; then
        log_error "Файл бэкапа не существует: $backup_file"
        return 1
    fi
    
    docker run --rm \
        -v "$BACKUP_DIR:/backup" \
        alpine \
        tar tzf "/backup/$(basename "$backup_file")" > /dev/null
    
    if [ $? -ne 0 ]; then
        log_error "Бэкап поврежден: $backup_file"
        return 1
    fi
    
    log_info "Бэкап прошел проверку целостности"
    return 0
}

# Проверка состояния Prometheus до бэкапа
check_prometheus_status() {
    local compose_cmd=$(get_docker_compose_cmd)
    
    cd "$(dirname "$DOCKER_COMPOSE_PATH")"
    $compose_cmd ps prometheus | grep -q "Up"
    
    if [ $? -eq 0 ]; then
        log_info "Prometheus работает перед бэкапом"
        return 0
    else
        log_warn "Prometheus не работает перед бэкапом"
        return 1
    fi
}

# Основная функция
main() {
    log_info "=== Запуск еженедельного бэкапа Prometheus ==="
    
    # Проверки
    check_dependencies
    create_backup_dir
    
    # Проверяем статус Prometheus
    check_prometheus_status
    local was_running=$?
    
    # Останавливаем Prometheus только если он был запущен
    if [ "$was_running" -eq 0 ]; then
        if ! stop_prometheus; then
            log_error "Не удалось остановить Prometheus, прерывание"
            exit 1
        fi
    else
        log_info "Prometheus уже остановлен, продолжаем бэкап"
    fi
    
    # Создаем бэкап
    local backup_file
    backup_file=$(create_backup)
    if [ $? -ne 0 ]; then
        log_error "Не удалось создать бэкап"
        # Пытаемся запустить Prometheus если он был запущен
        if [ "$was_running" -eq 0 ]; then
            start_prometheus
        fi
        exit 1
    fi
    
    # Проверяем бэкап
    if ! verify_backup "$backup_file"; then
        log_error "Бэкап не прошел проверку"
        rm -f "$backup_file"
        if [ "$was_running" -eq 0 ]; then
            start_prometheus
        fi
        exit 1
    fi
    
    # Запускаем Prometheus только если он был запущен до бэкапа
    if [ "$was_running" -eq 0 ]; then
        if ! start_prometheus; then
            log_error "Не удалось запустить Prometheus после бэкапа"
            exit 1
        fi
    else
        log_info "Prometheus был остановлен до бэкапа, не запускаем обратно"
    fi
    
    # Очищаем старые бэкапы
    cleanup_old_backups
    
    log_info "=== Бэкап завершен успешно ==="
}

# Обработка сигналов
trap 'log_error "Скрипт прерван"; if [ "$was_running" -eq 0 ]; then start_prometheus; fi; exit 1' INT TERM

# Запуск основной функции
main
