#!/bin/bash
#
# crear-cliente-vpn.sh - Genera configuracion cliente WireGuard
#

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Error: Este script debe ejecutarse como root (sudo)"
   exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <nombre_cliente> [ip_elastica]"
    exit 1
fi

CLIENTE="$1"
IP_ELASTICA="${2:-}"
WIREGUARD_DIR="/etc/wireguard"
CLIENTS_DIR="/etc/wireguard/clients"
WG_INTERFACE="wg0"
VPN_SUBNET="172.16.3"
AD_DNS="10.0.2.75"
PRIVATE_SUBNET="10.0.2.0/24"

mkdir -p "$CLIENTS_DIR"

# Detectar IP elastica automaticamente si no se proporciona
if [[ -z "$IP_ELASTICA" ]]; then
    IP_ELASTICA=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null)
    if [[ -z "$IP_ELASTICA" ]]; then
        echo "Error: No se pudo detectar la IP elastica automaticamente."
        exit 1
    fi
fi

# Leer clave publica del servidor WireGuard
SERVER_PUBKEY=$(cat "${WIREGUARD_DIR}/publickey" 2>/dev/null)
if [[ -z "$SERVER_PUBKEY" ]]; then
    echo "Error: No se encontro la clave publica del servidor."
    exit 1
fi

# Calcular siguiente IP disponible en el rango VPN
LAST_IP=$(grep -r "AllowedIPs" "${WIREGUARD_DIR}" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | grep "^${VPN_SUBNET}" | sort -t. -k4 -n | tail -1 | awk -F. '{print $4}')
if [[ -z "$LAST_IP" ]]; then
    CLIENT_IP=2
else
    CLIENT_IP=$((LAST_IP + 1))
fi

if [[ $CLIENT_IP -gt 254 ]]; then
    echo "Error: Se ha alcanzado el limite de clientes VPN (253)."
    exit 1
fi

CLIENT_ADDRESS="${VPN_SUBNET}.${CLIENT_IP}"

# Generar par de claves para el cliente y registrar peer en el servidor
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "${CLIENT_ADDRESS}/32"

# Persistir el peer en wg0.conf para que se conserve tras reinicios
{
  echo ""
  echo "[Peer]"
  echo "PublicKey = ${CLIENT_PUBLIC_KEY}"
  echo "AllowedIPs = ${CLIENT_ADDRESS}/32"
} >> "${WIREGUARD_DIR}/${WG_INTERFACE}.conf"

# Generar archivo de configuracion del cliente
CONFIG_FILE="${CLIENTS_DIR}/${CLIENTE}.conf"

cat > "$CONFIG_FILE" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_ADDRESS}/24
DNS = ${AD_DNS}

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${IP_ELASTICA}:51820
AllowedIPs = ${PRIVATE_SUBNET}, ${VPN_SUBNET}.0/24
PersistentKeepalive = 25
EOF

chmod 600 "$CONFIG_FILE"

echo "Cliente VPN $CLIENTE creado. Configuracion en $CONFIG_FILE"