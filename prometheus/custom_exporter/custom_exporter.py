#!/usr/bin/env python3

from prometheus_client import Gauge, start_http_server
import subprocess
import time
import logging

# Настройка логирования
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Создаем метрику
USER_COUNT = Gauge('node_active_users_count', 'Number of active user sessions')

def get_user_count():
    try:
        # Простая команда для подсчета уникальных пользователей
        result = subprocess.run(['who'], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            # Получаем список пользователей и считаем уникальные
            users = []
            for line in result.stdout.split('\n'):
                if line.strip():
                    parts = line.split()
                    if parts:
                        user = parts[0]
                        users.append(user)
            count = len(set(users))
            logger.info(f"Found {count} active users: {set(users)}")
            return count
        return 0
    except Exception as e:
        logger.error(f"Error getting user count: {e}")
        return 0

if __name__ == '__main__':
    try:
        logger.info("Starting Custom exporter on port 9101")
        # Запускаем HTTP-сервер на порту 9101
        start_http_server(9101)
        logger.info("Exporter started successfully")
        
        # Бесконечный цикл обновления метрик
        while True:
            count = get_user_count()
            USER_COUNT.set(count)
            time.sleep(30)
            
    except Exception as e:
        logger.error(f"Failed to start exporter: {e}")
        raise
