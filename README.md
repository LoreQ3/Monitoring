<h1 align="center" style="border-bottom: none">
    <a href="https://prometheus.io" target="_blank"><img alt="Prometheus" src="https://github.com/LoreQ3/Monitoring/blob/main/img/img4.png"></a><br>Prometheus
</h1>

Система мониторинга Prometheus+Grafana, развернутая на docker-compose с основными необходимыми экспортерами:
- node-exporter
- snmp-exporter
- capadvisor

Оповещения организованы через Alertmanager через Telegram. 

Добавлена кастомная метрика количества уникальных пользователей на сервере Linux.

С целью обеспечения безопасности доступ к Grafana организован через сервер Nginx.

Добавлены скрипты с целью выполнения еженедельного бэкапа метрик и логирования.

А так же полезные скрипты для автоматизации установки сервисов мониторинга.
![Скриншот](https://github.com/LoreQ3/Monitoring/blob/main/img/img1.png)
![Скриншот](https://github.com/LoreQ3/Monitoring/blob/main/img/img2.png)
![Скриншот](https://github.com/LoreQ3/Monitoring/blob/main/img/img3.png)
