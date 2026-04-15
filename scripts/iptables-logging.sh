#!/bin/bash
#
# iptables-logging.sh - Configura reglas LOG de iptables y rotacion de logs
#

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Error: Este script debe ejecutarse como root (sudo)"
    exit 1
fi

# Anadir reglas LOG para registrar paquetes denegados
if ! iptables -C INPUT -j LOG --log-prefix "IPTables-Dropped: " --log-level 4 2>/dev/null; then
    iptables -A INPUT -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
fi

if ! iptables -C FORWARD -j LOG --log-prefix "IPTables-Dropped: " --log-level 4 2>/dev/null; then
    iptables -A FORWARD -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
fi

# Habilitar log de paquetes sospechosos (martians)
sysctl -w net.ipv4.conf.all.log_martians=1 2>/dev/null || true
sysctl -w net.ipv4.conf.default.log_martians=1 2>/dev/null || true
echo "net.ipv4.conf.all.log_martians=1" >> /etc/sysctl.conf 2>/dev/null || true
echo "net.ipv4.conf.default.log_martians=1" >> /etc/sysctl.conf 2>/dev/null || true

# Persistir reglas de iptables
netfilter-persistent save 2>/dev/null || {
    apt-get update -qq && apt-get install -y iptables-persistent netfilter-persistent
    netfilter-persistent save
}

# Configurar logrotate para kern.log
cat > /etc/logrotate.d/kern-log <<'EOF'
/var/log/kern.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 syslog adm
}
EOF

# Crear directorio para metricas custom de Node Exporter (textfile collector)
TEXTFILE_DIR="/var/lib/prometheus/node-exporter"
mkdir -p "$TEXTFILE_DIR"
chown prometheus:prometheus "$TEXTFILE_DIR" 2>/dev/null || true

echo "Configuracion de logging de iptables completada."