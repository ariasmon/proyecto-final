#!/bin/bash
#
# iptables-metrics.sh - Recopila metricas de paquetes denegados por iptables para Prometheus
#

TEXTFILE_DIR="/var/lib/prometheus/node-exporter"
METRIC_FILE="$TEXTFILE_DIR/iptables.prom"
TMP_FILE="$METRIC_FILE.tmp"

mkdir -p "$TEXTFILE_DIR"

# Leer contadores de paquetes denegados desde iptables
INPUT_DROPPED=$(iptables -L INPUT -v -n 2>/dev/null | grep "LOG.*IPTables-Dropped" | awk '{print $1}' | head -1)
FORWARD_DROPPED=$(iptables -L FORWARD -v -n 2>/dev/null | grep "LOG.*IPTables-Dropped" | awk '{print $1}' | head -1)

# Si no hay regla LOG, asignar 0
INPUT_DROPPED=${INPUT_DROPPED:-0}
FORWARD_DROPPED=${FORWARD_DROPPED:-0}

# Escribir metrica en formato Prometheus para textfile collector
cat > "$TMP_FILE" <<EOF
# HELP iptables_dropped_packets_total Total number of packets logged as dropped by iptables
# TYPE iptables_dropped_packets_total counter
iptables_dropped_packets_total{chain="INPUT"} $INPUT_DROPPED
iptables_dropped_packets_total{chain="FORWARD"} $FORWARD_DROPPED
EOF

mv "$TMP_FILE" "$METRIC_FILE"