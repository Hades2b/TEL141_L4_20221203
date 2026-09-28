#!/bin/bash
# create_network_vlan.sh
# Uso: bash -s -- <VLAN_ID> <CIDR> <DHCP_ENABLED> [<DHCP_RANGE: start_ip,end_ip,mask>]
# Ejemplo: bash -s -- 100 192.168.0.0/24 yes 192.168.0.10,192.168.0.100

set -euo pipefail

# --- Parámetros ---
VLAN_ID=${1:?"Error: VLAN_ID no proporcionado."}
CIDR=${2:?"Error: CIDR no proporcionado."}
DHCP_ENABLED=${3:?"Error: elija yes/no para habilitar DHCP."}
DHCP_RANGE=${4:-}

BRIDGE="br-int"
GW_IFACE="gw_vlan${VLAN_ID}"
NS_NAME="ns_dhcp_vlan${VLAN_ID}"
VETH_OVS="veth_ovs_v${VLAN_ID}"
VETH_NS="veth_ns_v${VLAN_ID}"

# --- Validaciones ---
if [ "$DHCP_ENABLED" = "yes" ] && [ -z "$DHCP_RANGE" ]; then
    echo "Error: DHCP habilitado pero no se proporcionó rango DHCP."
    exit 1
fi
if ! sudo ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    echo "Error: El bridge $BRIDGE no existe. Ejecute init_master.sh primero."
    exit 1
fi

# --- Cálculo de parametros de red ---
NETWORK="${CIDR%/*}"
PREFIX="${CIDR#*/}"

maskarr=(255 255 255 0)
if [[ $((PREFIX)) -lt 8 ]]; then
    maskarr=($((256-2**(8-PREFIX))) 0 0 0)
elif  [[ $((PREFIX)) -lt 16 ]]; then
    maskarr=(255 $((256-2**(16-PREFIX))) 0 0)
elif  [[ $((PREFIX)) -lt 24 ]]; then
    maskarr=(255 255 $((256-2**(24-PREFIX))) 0)
elif [[ $((PREFIX)) -lt 32 ]]; then
        maskarr=(255 255 255 $((256-2**(32-PREFIX))))
elif [[ ${PREFIX} == 32 ]]; then
    echo "Error: No se puede usar /32 como máscara de red."
    exit 1
fi
NETMASK="${maskarr[0]}.${maskarr[1]}.${maskarr[2]}.${maskarr[3]}"

IFS=',' read -r DHCP_START DHCP_END <<< "$DHCP_RANGE"
IFS='.' read -r a b c d <<< "$NETWORK"
GATEWAY_IP="$a.$b.$c.$((d+1))"
NETNS_IP="$a.$b.$c.$((d+2))"

echo "[i] VLAN: $VLAN_ID, Red: $CIDR"
echo "[i] Gateway (1ra IP): $GATEWAY_IP/$PREFIX"
if [ "$DHCP_ENABLED" = "yes" ]; then
    echo "[i] DHCP habilitado. Rango: $DHCP_RANGE"
    echo "[i] Namespace DHCP: $NS_NAME, IP: $NETNS_IP/$PREFIX"
fi

# --- Limpieza previa ---
echo "[+] Limpiando configuración previa para VLAN $VLAN_ID..."
# Eliminar namespace si existe
if ip netns list | grep -q "^$NS_NAME"; then
    sudo ip netns del "$NS_NAME" || true
fi
# Eliminar puertos OVS si existen
sudo ovs-vsctl --if-exists del-port "$BRIDGE" "$GW_IFACE" || true
sudo ovs-vsctl --if-exists del-port "$BRIDGE" "$VETH_OVS" || true
# Eliminar interfaces veth si existen
sudo ip link del "$VETH_OVS" 2>/dev/null || true

# --- 1. Crear interfaz interna en OVS (gateway) ---
echo "[+] Creando interfaz interna $GW_IFACE en $BRIDGE con tag $VLAN_ID"
sudo ovs-vsctl add-port "$BRIDGE" "$GW_IFACE" tag="$VLAN_ID" -- set interface "$GW_IFACE" type=internal
sudo ip addr add "${GATEWAY_IP}/${PREFIX}" dev "$GW_IFACE"
sudo ip link set dev "$GW_IFACE" up

# --- 2. Configurar DHCP si está habilitado ---
if [ "$DHCP_ENABLED" = "yes" ]; then
    echo "[+] Configurando DHCP en namespace $NS_NAME"
    # Crear namespace
    sudo ip netns add "$NS_NAME"
    # Crear par veth
    sudo ip link add "$VETH_OVS" type veth peer name "$VETH_NS"
    # Conectar extremo veth al bridge ovs con tag
    sudo ovs-vsctl add-port "$BRIDGE" "$VETH_OVS" tag="$VLAN_ID"
    sudo ip link set dev "$VETH_OVS" up
    # Conectar extremo veth al namespace
    sudo ip link set "$VETH_NS" netns "$NS_NAME"
    sudo ip netns exec "$NS_NAME" ip link set lo up
    sudo ip netns exec "$NS_NAME" ip link set "$VETH_NS" up
    sudo ip netns exec "$NS_NAME" ip addr add "${NETNS_IP}/${PREFIX}" dev "$VETH_NS"

    DHCP_START=$(echo "$DHCP_RANGE" | cut -d',' -f1)
    DHCP_END=$(echo "$DHCP_RANGE" | cut -d',' -f2)

    echo "[+] Iniciando dnsmasq en namespace $NS_NAME"
    sudo ip netns exec "$NS_NAME" dnsmasq \
        --conf-file=/dev/null \
        --interface="$VETH_NS" \
        --dhcp-range="${DHCP_START},${DHCP_END},${NETMASK},12h" \
        --dhcp-option=3,"$GATEWAY_IP" \
        --dhcp-option=6,8.8.8.8 \
        --pid-file="/tmp/dnsmasq_${VLAN_ID}.pid" \
        --log-dhcp

    echo "[+] dnsmasq iniciado (PID guardado en /tmp/dnsmasq_${VLAN_ID}.pid)"
fi

echo "[OK] create_network_vlan.sh finalizado para VLAN $VLAN_ID:$CIDR"