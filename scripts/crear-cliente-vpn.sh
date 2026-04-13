#!/bin/bash
#
# crear-cliente-vpn.sh - Genera configuracion cliente WireGuard para TFG
#
# USO:
#     sudo ./crear-cliente-vpn.sh <nombre_cliente> [ip_elastica]
#
# DESCRIPCION:
#     Este script automatiza la creacion de clientes VPN para conectarse
#     a la infraestructura del TFG y acceder al dominio Active Directory.
#
#     Requisitos:
#     - WireGuard debe estar instalado y configurado en el servidor
#     - El servidor VPN debe tener la interfaz wg0 activa
#     - Ejecutar como root (sudo)
#
# PARAMETROS:
#     nombre_cliente  - Nombre identificador del cliente (ej: usuario1, portatil_juan)
#     ip_elastica     - IP elastica del Gateway (opcional, se autodetecta si no se proporciona)
#
# CONFIGURACION GENERADA:
#     - Rango VPN: 172.16.3.0/24
#     - DNS: 10.0.2.75 (Controlador de Dominio Active Directory)
#     - Acceso: Subred privada (10.0.2.0/24) y VPN (172.16.3.0/24)
#
# EJEMPLOS:
#     sudo ./crear-cliente-vpn.sh usuario1
#     sudo ./crear-cliente-vpn.sh portatil_juan 54.123.45.67
#

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Error: Este script debe ejecutarse como root (sudo)"
   exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <nombre_cliente> [ip_elastica]"
    echo ""
    echo "Ejemplos:"
    echo "  sudo $0 usuario1"
    echo "  sudo $0 portatil_juan 54.123.45.67"
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

echo "=============================================="
echo "Creando cliente VPN: $CLIENTE"
echo "=============================================="

mkdir -p "$CLIENTS_DIR"

if [[ -z "$IP_ELASTICA" ]]; then
    IP_ELASTICA=$(curl -s https://api.ipify.org 2>/dev/null ||curl -s https://ifconfig.me 2>/dev/null)
    if [[ -z "$IP_ELASTICA" ]]; then
        echo "Error: No se pudo detectar la IP elastica automaticamente."
        echo "Por favor, proporciona la IP elastica como segundo parametro."
        echo "Uso: $0 $CLIENTE <ip_elastica>"
        exit 1
    fi
fi

echo "IP elastica detectada: $IP_ELASTICA"

SERVER_PUBKEY=$(cat "${WIREGUARD_DIR}/publickey" 2>/dev/null)
if [[ -z "$SERVER_PUBKEY" ]]; then
    echo "Error: No se encontro la clave publica del servidor."
    echo "Asegurate de que WireGuard esta configurado correctamente."
    exit 1
fi

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
echo "IP asignada al cliente: $CLIENT_ADDRESS"

echo "Generando par de claves para el cliente..."
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

echo "Anadiendo peer al servidor WireGuard..."
wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "${CLIENT_ADDRESS}/32"

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

echo ""
echo "=============================================="
echo "Cliente VPN creado exitosamente"
echo "=============================================="
echo ""
echo "Nombre del cliente: $CLIENTE"
echo "Direccion IP VPN: $CLIENT_ADDRESS"
echo "Archivo de configuracion: $CONFIG_FILE"
echo ""
echo "Contenido del archivo de configuracion:"
echo "-------------------------------------------"
cat "$CONFIG_FILE"
echo "-------------------------------------------"
echo ""
echo "INSTRUCCIONES PARA EL CLIENTE:"
echo ""
echo "1. Copia el archivo $CONFIG_FILE al dispositivo cliente"
echo "2. Importa el archivo .conf en la aplicacion WireGuard"
echo "3. Conecta a la VPN"
echo "4. Para unirte al dominio Active Directory (tfg.vp):"
echo "   - Windows: Configuracion -> Sistema -> Acerca de -> Unirse a un dominio"
echo "   - Introduce el dominio: tfg.vp"
echo "   - Credenciales de administrador del dominio"
echo ""
echo "NOTA: El DNS esta configurado para apuntar al controlador de dominio (${AD_DNS})"
echo ""
echo "Para ver los clientes conectados:"
echo "    sudo wg show"
echo ""
