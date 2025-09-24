FROM prom/node-exporter:latest

# Добавляем необходимые возможности
USER root

# Убедимся, что все необходимые точки монтирования доступны
VOLUME ["/proc", "/sys", "/"]

EXPOSE 9100
