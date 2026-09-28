#!/bin/bash
# routing_networks.sh
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

for IFACE in "$GW_IFACE_1" "$GW_IFACE_2"; do
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        echo "Error: la interfaz $IFACE no existe."
        exit 1
    fi
done

echo "[i] Habilitando enrutamiento entre VLAN $VLAN_ID_1 ($GW_IFACE_1) y VLAN $VLAN_ID_2 ($GW_IFACE_2)"
sudo iptables -A FORWARD -i "$GW_IFACE_1" -o "$GW_IFACE_2" -j ACCEPT
sudo iptables -A FORWARD -i "$GW_IFACE_2" -o "$GW_IFACE_1" -j ACCEPT

echo "[OK] routing_networks.sh finalizado (VLAN $VLAN_ID_1 <-> VLAN $VLAN_ID_2)"