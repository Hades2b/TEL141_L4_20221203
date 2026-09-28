#!/bin/bash
# no_internet_to_network.sh
# Uso: bash -s -- <VLAN_ID> <CIDR> [<EXT_IFACE>]
# Ejemplo: bash -s -- 100 192.168.0.0/24 ens3

set -euo pipefail

# --- Parámetros ---
VLAN_ID=${1:?"Error: VLAN_ID no proporcionado."}
CIDR=${2:?"Error: CIDR no proporcionado."}
EXT_IFACE=${3:-ens3}

GW_IFACE="gw_vlan${VLAN_ID}"

echo "[i] Eliminando salida a Internet para VLAN $VLAN_ID (red $CIDR) vía $EXT_IFACE"
# Eliminar reglas de FORWARD
while sudo iptables -C FORWARD -i "$GW_IFACE" -o "$EXT_IFACE" -s "$CIDR" -j ACCEPT 2>/dev/null; do
    sudo iptables -D FORWARD -i "$GW_IFACE" -o "$EXT_IFACE" -s "$CIDR" -j ACCEPT
fi
# Eliminar regla de NAT (MASQUERADE)
while sudo iptables -t nat -C POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null; do
    sudo iptables -t nat -D POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE
fi

echo "[OK] no_internet_to_network.sh finalizado para VLAN $VLAN_ID"