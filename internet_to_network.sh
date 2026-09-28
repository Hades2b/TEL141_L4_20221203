#!/bin/bash
# internet_to_network.sh
# Uso: bash -s -- <VLAN_ID> <CIDR> [<EXT_IFACE>]
# Ejemplo: bash -s -- 100 192.168.0.0/24 ens3

set -euo pipefail

# --- Parámetros ---
VLAN_ID=${1:?"Error: VLAN_ID no proporcionado."}
CIDR=${2:?"Error: CIDR no proporcionado."}
EXT_IFACE=${3:-ens3}

GW_IFACE="gw_vlan${VLAN_ID}"

# --- Validaciones ---
if ! ip link show "$EXT_IFACE" >/dev/null 2>&1; then
    echo "Error: la interfaz externa $EXT_IFACE no existe."
    exit 1
fi
if ! ip link show "$GW_IFACE" >/dev/null 2>&1; then
    echo "Error: la interfaz de gateway $GW_IFACE no existe. Ejecute create_network_vlan.sh primero."
    exit 1
fi

echo "[i] Habilitando salida a Internet para VLAN $VLAN_ID (red $CIDR) vía $EXT_IFACE"
# Reglas de FORWARD
if ! sudo iptables -C FORWARD -i "$GW_IFACE" -o "$EXT_IFACE" -s "$CIDR" -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -i "$GW_IFACE" -o "$EXT_IFACE" -s "$CIDR" -j ACCEPT
fi
# Regla de NAT (MASQUERADE)
if ! sudo iptables -t nat -C POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE
fi

echo "[OK] internet_to_network.sh finalizado para VLAN $VLAN_ID"