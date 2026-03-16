#!/bin/bash
echo "🚀 Iniciando configuración del Gateway TFG..."

# 1. Habilitar IP Forwarding en el Kernel
sudo sysctl -w net.ipv4.ip_forward=1

# 2. Reglas de Enrutamiento (NAT) y Port Forwarding (RDP)
sudo iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o ens5 -j MASQUERADE
sudo iptables -t nat -A PREROUTING -p tcp --dport 3389 -j DNAT --to-destination 10.0.2.75:3389

# 3. Hacer las reglas persistentes
echo "📦 Instalando iptables-persistent..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install iptables-persistent netfilter-persistent -y
sudo netfilter-persistent save

echo "✅ ¡Configuración terminada!"
