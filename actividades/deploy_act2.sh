#!/bin/bash
# deploy_act2.sh
# Actividad 2: Redes aisladas SIN DHCP y CON salida a Internet
# Topología:
#   Server 1 (worker): 1 VM VLAN 100  + 1 VM VLAN 200
#   Server 2 (worker): 1 VM VLAN 100  + 1 VM VLAN 200
#   Server 3 (master): gateways + NAT

set -euo pipefail

SCRIPTS_DIR=".."

# --- Nodos ---
SERVER1="10.0.10.1"
SERVER2="10.0.10.2"
SERVER3="10.0.10.3"

# --- Interfaces ---
DATA_IFACE="ens4"
EXT_IFACE="ens3"

# --- VLAN 100 ---
VLAN_100_ID=100
VLAN_100_CIDR="192.168.0.0/24"

# --- VLAN 200 ---
VLAN_200_ID=200
VLAN_200_CIDR="192.168.2.0/24"

# --- Nombres de VM ---
VM_S1_V100="vm1_vlan100"
VM_S1_V200="vm1_vlan200"
VM_S2_V100="vm2_vlan100"
VM_S2_V200="vm2_vlan200"


echo "[1/6] init_master.sh en Server 3"
ssh ubuntu@${SERVER3} "bash -s -- ${DATA_IFACE}" < "${SCRIPTS_DIR}/init_master.sh"

echo "[2/6] init_worker.sh en Server 1 y Server 2"
ssh ubuntu@${SERVER1} "bash -s -- ${DATA_IFACE}" < "${SCRIPTS_DIR}/init_worker.sh"
ssh ubuntu@${SERVER2} "bash -s -- ${DATA_IFACE}" < "${SCRIPTS_DIR}/init_worker.sh"

echo "[3/6] create_network_vlan.sh VLAN 100 (SIN DHCP) en Server 3"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_100_ID} ${VLAN_100_CIDR} no" < "${SCRIPTS_DIR}/create_network_vlan.sh"

echo "[4/6] create_network_vlan.sh VLAN 200 (SIN DHCP) en Server 3"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_200_ID} ${VLAN_200_CIDR} no" < "${SCRIPTS_DIR}/create_network_vlan.sh"

echo "[5/6] Creando 4 VMs (2 en Server 1, 2 en Server 2)"
ssh ubuntu@${SERVER1} "bash -s -- ${VM_S1_V100} br-int ${VLAN_100_ID} 1" < "${SCRIPTS_DIR}/create_vm.sh"
ssh ubuntu@${SERVER1} "bash -s -- ${VM_S1_V200} br-int ${VLAN_200_ID} 2" < "${SCRIPTS_DIR}/create_vm.sh"
ssh ubuntu@${SERVER2} "bash -s -- ${VM_S2_V100} br-int ${VLAN_100_ID} 1" < "${SCRIPTS_DIR}/create_vm.sh"
ssh ubuntu@${SERVER2} "bash -s -- ${VM_S2_V200} br-int ${VLAN_200_ID} 2" < "${SCRIPTS_DIR}/create_vm.sh"

echo "[6/6] Habilitando salida a Internet para VLAN 100 y 200"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_100_ID} ${VLAN_200_ID}" < "${SCRIPTS_DIR}/no_routing_networks.sh"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_100_ID} ${VLAN_100_CIDR} ${EXT_IFACE}" < "${SCRIPTS_DIR}/internet_to_network.sh"
ssh ubuntu@${SERVER3} "bash -s -- ${VLAN_200_ID} ${VLAN_200_CIDR} ${EXT_IFACE}" < "${SCRIPTS_DIR}/internet_to_network.sh"


cat <<EOF
[READY] Actividad 2 desplegada

SERVIDOR      VM               VLAN   IP               GW              VNC
---------     --------------   -----  -------------    ------------    ---------
SERVER1       ${VM_S1_V100}    100    192.168.0.10     192.168.0.1     :1 (5901)
SERVER2       ${VM_S2_V100}    100    192.168.0.11     192.168.0.1     :2 (5902)
SERVER1       ${VM_S1_V200}    200    192.168.2.10     192.168.2.1     :1 (5901)
SERVER2       ${VM_S2_V200}    200    192.168.2.11     192.168.2.1     :2 (5902)

CONFIGURAR: VMs necesitan IPs y GW vía VNC.
EOF