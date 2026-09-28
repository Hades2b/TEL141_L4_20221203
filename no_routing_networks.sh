#!/bin/bash
# no_routing_networks.sh
# Uso: bash -s -- <VLAN_ID_1> <VLAN_ID_2>
# Ejemplo: bash -s -- 100 200

set -euo pipefail

# --- Parámetros ---
VLAN_ID_1=${1:?"Error: VLAN_ID_1 no proporcionado."}
VLAN_ID_2=${2:?"Error: VLAN_ID_2 no proporcionado."}

GW_IFACE_1="gw_vlan${VLAN_ID_1}"
GW_IFACE_2="gw_vlan${VLAN_ID_2}"

if [ "$VLAN_ID_1" = "$VLAN_ID_2" ]; then
    echo "Error: las VLANs deben ser distintas."
    exit 1
fi

echo "[i] Eliminando enrutamiento entre VLAN $VLAN_ID_1 ($GW_IFACE_1) y VLAN $VLAN_ID_2 ($GW_IFACE_2)"
if sudo iptables -C FORWARD -i "$GW_IFACE_1" -o "$GW_IFACE_2" -j ACCEPT 2>/dev/null; then
    sudo iptables -D FORWARD -i "$GW_IFACE_1" -o "$GW_IFACE_2" -j ACCEPT
fi
if sudo iptables -C FORWARD -i "$GW_IFACE_2" -o "$GW_IFACE_1" -j ACCEPT 2>/dev/null; then
    sudo iptables -D FORWARD -i "$GW_IFACE_2" -o "$GW_IFACE_1" -j ACCEPT
fi

echo "[OK] no_routing_networks.sh finalizado (VLAN $VLAN_ID_1 <-x-> VLAN $VLAN_ID_2)"