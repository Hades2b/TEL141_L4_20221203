#!/bin/bash
# cleanup.sh
# Limpia TODAS las actividades reutilizando los scripts modulares:
#   - delete_vm.sh
#   - no_internet_to_network.sh
#   - no_routing_networks.sh
# Lo demás (namespaces DHCP, gw_vlanX, br-int, huérfanos) va inline
# porque no existe un script específico para ello.
# Ejecutar desde Server 4

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Nodos ---
SERVER1="10.0.10.1"
SERVER2="10.0.10.2"
SERVER3="10.0.10.3"

# --- Interfaces ---
DATA_IFACE="ens4"
EXT_IFACE="ens3"

VLAN_100_ID=100
VLAN_100_CIDR="192.168.0.0/24"
VLAN_200_ID=200
VLAN_200_CIDR="192.168.2.0/24"

# Nombres de VM
VM_S1_V100="vm1_vlan100"
VM_S1_V200="vm1_vlan200"
VM_S2_V100="vm2_vlan100"
VM_S2_V200="vm2_vlan200"

echo "CLEANUP:  slice a estado limpio"

# 1) WORKERS: delete_vm.sh por cada VM + limpieza de br-int
echo "[1/4] Workers: eliminando VMs con delete_vm.sh"
# Server 1
ssh ubuntu@${SERVER1} "bash -s -- ${VM_S1_V100} br-int ${VLAN_100_ID} 1" < "${SCRIPTS_DIR}/delete_vm.sh"
ssh ubuntu@${SERVER1} "bash -s -- ${VM_S1_V200} br-int ${VLAN_200_ID} 2" < "${SCRIPTS_DIR}/delete_vm.sh"
# Server 2
ssh ubuntu@${SERVER2} "bash -s -- ${VM_S2_V100} br-int ${VLAN_100_ID} 1" < "${SCRIPTS_DIR}/delete_vm.sh"
ssh ubuntu@${SERVER2} "bash -s -- ${VM_S2_V200} br-int ${VLAN_200_ID} 2" < "${SCRIPTS_DIR}/delete_vm.sh"

echo "[2/4] Workers: barrido de huérfanos y eliminación de br-int"
for NODE in "${SERVER1}" "${SERVER2}"; do
    ssh ubuntu@${NODE} "bash -s -- ${DATA_IFACE}" <<'REMOTE'
set -uo pipefail
IFACE="${1:-ens4}"

# TAPs huérfanos que no estén en la lista de VMs conocidas
for TAP in $(sudo ip -br link show type tuntap 2>/dev/null | awk '{print $1}' | grep -E '_tap$' || true); do
    echo "  [+] TAP huérfano: $TAP"
    sudo ovs-vsctl --if-exists del-port br-int "$TAP" 2>/dev/null || true
    sudo ip link del "$TAP" 2>/dev/null || true
done

# QEMUs que sigan vivos (por si el nombre de VM no coincidía)
QEMU_PIDS=$(pgrep -f "qemu-system-x86_64" || true)
if [ -n "$QEMU_PIDS" ]; then
    echo "  [+] Matando QEMUs huérfanos: $QEMU_PIDS"
    for p in $QEMU_PIDS; do sudo kill -9 "$p" 2>/dev/null || true; done
fi

# Overlays huérfanos
if [ -d "$HOME/images" ]; then
    find "$HOME/images" -maxdepth 1 -name 'vm*.qcow2' -delete 2>/dev/null || true
fi

# Borrar br-int y reconectar ens4
if sudo ovs-vsctl br-exists br-int 2>/dev/null; then
    sudo ovs-vsctl --if-exists del-port br-int "$IFACE" || true
    sudo ovs-vsctl --if-exists del-br br-int || true
    echo "  [+] br-int eliminado"
fi
sudo ip link set "$IFACE" up 2>/dev/null || true
REMOTE
done

# 3) MASTER: quitar NAT, routing, namespaces DHCP, gw_vlanX, br-int
echo "[3/4] Master: quitando NAT con no_internet_to_network.sh"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_100_ID} ${VLAN_100_CIDR} ${EXT_IFACE}" < "${SCRIPTS_DIR}/no_internet_to_network.sh"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_200_ID} ${VLAN_200_CIDR} ${EXT_IFACE}" < "${SCRIPTS_DIR}/no_internet_to_network.sh"

echo "[3/4] Master: quitando routing con no_routing_networks.sh"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_100_ID} ${VLAN_200_ID}" < "${SCRIPTS_DIR}/no_routing_networks.sh"

echo "[3/4] Master: limpieza de namespaces DHCP, gw_vlanX, br-int y huérfanos"
ssh ubuntu@${SERVER3} "bash -s -- ${DATA_IFACE}" <<'REMOTE'
set -uo pipefail
IFACE="${1:-ens4}"

# Namespaces DHCP
for NS in $(sudo ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^ns_dhcp_vlan' || true); do
    echo "  [+] Eliminando namespace $NS"
    sudo ip netns pids "$NS" 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
    sudo ip netns del "$NS" || true
done

# veths huérfanos del DHCP
for V in $(sudo ip -br link show 2>/dev/null | awk '{print $1}' | grep -E '^veth_(ovs|ns)' || true); do
    echo "  [+] veth huérfano: $V"
    sudo ip link del "$V" 2>/dev/null || true
done

# Puertos gw_vlanX en OVS e interfaces del kernel
if sudo ovs-vsctl br-exists br-int 2>/dev/null; then
    for P in $(sudo ovs-vsctl list-ports br-int 2>/dev/null | grep -E '^gw_vlan' || true); do
        echo "  [+] Puerto OVS: $P"
        sudo ovs-vsctl --if-exists del-port br-int "$P" || true
    done
fi
for I in $(ip -br link show 2>/dev/null | awk '{print $1}' | grep -E '^gw_vlan' || true); do
    echo "  [+] Interfaz kernel: $I"
    sudo ip link del "$I" 2>/dev/null || true
done

# Borrar br-int
if sudo ovs-vsctl br-exists br-int 2>/dev/null; then
    sudo ovs-vsctl --if-exists del-port br-int "$IFACE" || true
    sudo ovs-vsctl --if-exists del-br br-int || true
    echo "  [+] br-int eliminado"
fi
sudo ip link set "$IFACE" up 2>/dev/null || true


REMOTE


echo " [CLEAN] Cleanup completado"
