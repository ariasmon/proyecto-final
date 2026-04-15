#!/bin/bash
#
# bootstrap.sh - Configuracion completa del Gateway Ubuntu para TFG
#

set -e

GITHUB_REPO="https://github.com/ariasmon/proyecto-final.git"
DEPLOY_DIR="/home/ubuntu/despliegue"

echo "=============================================="
echo "Bootstrap del Gateway Ubuntu - TFG"
echo "=============================================="
echo ""

# ============================================================================
# VERIFICACION: ¿Ya esta configurado?
# ============================================================================
if systemctl is-active --quiet prometheus 2>/dev/null; then
    echo "El Gateway ya parece estar configurado (Prometheus esta activo)."
    echo "Ejecutar bootstrap de nuevo sobrescribira configs y preguntara tokens."
    echo -n "¿Continuar de todas formas? [N/y]: "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Abortado. Para reconfigurar, ejecuta este script con 'y'."
        exit 0
    fi
    echo "Continuando..."
fi

# ============================================================================
# PASO 1: Actualizar sistema
# ============================================================================
echo "[1/11] Actualizando sistema..."
apt-get update -y
apt-get upgrade -y

# ============================================================================
# PASO 2: Instalar software desde repositorios apt
# ============================================================================
echo "[2/11] Instalando software base..."
apt-get install -y prometheus prometheus-node-exporter grafana wireguard \
  iptables-persistent netfilter-persistent curl python3 jq

# ============================================================================
# PASO 3: Instalar Alertmanager 0.28.1 desde release
# ============================================================================
echo "[3/11] Instalando Alertmanager 0.28.1..."
cd /tmp
wget -q https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz
tar xzf alertmanager-0.28.1.linux-amd64.tar.gz
systemctl stop prometheus-alertmanager 2>/dev/null || true
cp alertmanager-0.28.1.linux-amd64/alertmanager /usr/bin/prometheus-alertmanager
chmod +x /usr/bin/prometheus-alertmanager
mkdir -p /var/lib/prometheus/alertmanager
chown -R prometheus:prometheus /var/lib/prometheus/alertmanager

# ============================================================================
# PASO 4: Clonar repositorio
# ============================================================================
echo "[4/11] Clonando repositorio..."
if [ -d "$DEPLOY_DIR" ]; then
    echo "Repositorio ya existe, actualizando..."
    git -C "$DEPLOY_DIR" pull origin main
else
    git clone "$GITHUB_REPO" "$DEPLOY_DIR"
fi

# ============================================================================
# PASO 5: Copiar configs
# ============================================================================
echo "[5/11] Copiando configs..."
cp "$DEPLOY_DIR"/configs/prometheus.yml /etc/prometheus/
cp "$DEPLOY_DIR"/configs/alert_rules.yml /etc/prometheus/
cp "$DEPLOY_DIR"/configs/alertmanager.yml.example /etc/prometheus/alertmanager.yml
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# ============================================================================
# PASO 6: Preguntar tokens Telegram (interactivo)
# ============================================================================
echo "[6/11] Configuracion de Telegram..."
echo ""
echo "=============================================="
echo "Configuracion de Alertmanager - Telegram"
echo "=============================================="
echo ""
echo "Token del bot de Telegram:"
read -r BOT_TOKEN
echo "Chat ID del grupo de Telegram:"
read -r CHAT_ID

sed -i "s/TU_BOT_TOKEN_AQUI/$BOT_TOKEN/" /etc/prometheus/alertmanager.yml
sed -i "s/TU_CHAT_ID_AQUI/$CHAT_ID/" /etc/prometheus/alertmanager.yml

echo "Tokens aplicados correctamente."

# ============================================================================
# PASO 7: Configurar iptables-logging
# ============================================================================
echo "[7/11] Configurando logging de iptables..."
cp "$DEPLOY_DIR"/scripts/iptables-logging.sh /opt/
chmod +x /opt/iptables-logging.sh
bash /opt/iptables-logging.sh

# ============================================================================
# PASO 8: Configurar iptables-metrics y Node Exporter textfile
# ============================================================================
echo "[8/11] Configurando metricas de iptables..."
cp "$DEPLOY_DIR"/scripts/iptables-metrics.sh /opt/
chmod +x /opt/iptables-metrics.sh

mkdir -p /var/lib/prometheus/node-exporter
chown prometheus:prometheus /var/lib/prometheus/node-exporter 2>/dev/null || true

echo 'ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"' \
  > /etc/default/prometheus-node-exporter

echo "* * * * * root /opt/iptables-metrics.sh" > /etc/cron.d/iptables-metrics

systemctl restart prometheus-node-exporter

# ============================================================================
# PASO 9: Configurar WireGuard
# ============================================================================
echo "[9/11] Configurando WireGuard..."

if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "Generando claves WireGuard..."
    wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
    chmod 600 /etc/wireguard/privatekey

    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/privatekey)

    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 172.16.3.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIVATE_KEY}

# Peers se anaden con crear-cliente-vpn.sh
EOF

    echo "Configuracion WireGuard creada."
else
    echo "WireGuard ya configurado, omitiendo."
fi

# Asegurar que la regla MASQUERADE VPN existe
if ! iptables -t nat -C POSTROUTING -s 172.16.3.0/24 -d 10.0.2.0/24 -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s 172.16.3.0/24 -d 10.0.2.0/24 -j MASQUERADE
    netfilter-persistent save
fi

# ============================================================================
# PASO 10: Habilitar e iniciar servicios
# ============================================================================
echo "[10/11] Habilitando servicios..."

systemctl enable prometheus prometheus-node-exporter grafana-server \
  prometheus-alertmanager wg-quick@wg0

systemctl restart prometheus-node-exporter
systemctl restart prometheus
systemctl restart prometheus-alertmanager
systemctl restart grafana-server
systemctl enable --now wg-quick@wg0 2>/dev/null || systemctl start wg-quick@wg0

echo "Servicios habilitados."

# ============================================================================
# PASO 11: Verificacion
# ============================================================================
echo "[11/11] Verificando servicios..."
echo ""
echo "=============================================="
echo "Estado de servicios"
echo "=============================================="

SERVICES="prometheus prometheus-node-exporter grafana-server prometheus-alertmanager wg-quick@wg0"
ALL_OK=true

for service in $SERVICES; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service"
    else
        echo "✗ $service - FALLO"
        ALL_OK=false
    fi
done

echo ""
echo "Puertos en escucha:"
ss -tlnp | grep -E "9090|9100|3000|9093|51820" || echo "(ninguno detected)"

echo ""
echo "=============================================="
echo "Bootstrap completado"
echo "=============================================="
echo ""
echo "Siguientes pasos:"
echo "  - Acceder a Grafana: http://<IP_GATEWAY>:3000"
echo "  - Acceder a Prometheus: http://<IP_GATEWAY>:9090"
echo "  - Ver clientes VPN: sudo wg show"
echo "  - Para crear cliente VPN: sudo $DEPLOY_DIR/scripts/crear-cliente-vpn.sh <nombre>"
echo ""