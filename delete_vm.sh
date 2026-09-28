#!/bin/bash
# delete_vm.sh
# Uso: bash -s -- <VM_NAME> <OVS_BRIDGE> <VLAN_ID> <VNC_PORT>
# Ejemplo: bash -s -- vm_vlan100 br-int 100 1

set -euo pipefail

# --- Parámetros ---
VM_NAME=${1:?"Error: VM_NAME no proporcionado."}
OVS_BRIDGE=${2:?"Error: OVS_BRIDGE no proporcionado."}
VLAN_ID=${3:?"Error: VLAN_ID no proporcionado."}
VNC_PORT=${4:?"Error: VNC_PORT no proporcionado."}

# --- Configuración ---
IMG_DIR="$HOME/images"
OVERLAY_IMG="${IMG_DIR}/${VM_NAME}.qcow2"
TAP_IFACE="${VM_NAME}_tap"
PID_FILE="/tmp/${VM_NAME}.pid"

echo "[i] Eliminando VM: $VM_NAME (VLAN $VLAN_ID, VNC :$VNC_PORT)"

# --- 1. Detener QEMU ---
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(sudo cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && sudo kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[+] Deteniendo QEMU (PID $OLD_PID)"
        sudo kill "$OLD_PID" 2>/dev/null || true
        for i in 1 2 3; do
            sudo kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 1
        done
        if sudo kill -0 "$OLD_PID" 2>/dev/null; then
            echo "[!] QEMU no terminó, forzando con SIGKILL"
            sudo kill -9 "$OLD_PID" 2>/dev/null || true
        fi
    else
        echo "[=] No hay proceso QEMU activo asociado a $PID_FILE"
    fi
    rm -f "$PID_FILE"
else
    echo "[=] No se encontró PID file $PID_FILE"
fi

# --- 2. Desconectar TAP del OVS ---
if sudo ovs-vsctl br-exists "$OVS_BRIDGE" 2>/dev/null; then
    if sudo ovs-vsctl port-to-br "$TAP_IFACE" >/dev/null 2>&1; then
        echo "[+] Eliminando $TAP_IFACE del bridge $OVS_BRIDGE"
        sudo ovs-vsctl del-port "$OVS_BRIDGE" "$TAP_IFACE"
    else
        echo "[=] $TAP_IFACE no está conectada a $OVS_BRIDGE"
    fi
else
    echo "[=] El bridge $OVS_BRIDGE no existe"
fi

# --- 3. Eliminar TAP del sistema ---
if ip link show "$TAP_IFACE" >/dev/null 2>&1; then
    echo "[+] Eliminando interfaz TAP $TAP_IFACE"
    sudo ip link del "$TAP_IFACE" || true
else
    echo "[=] Interfaz TAP $TAP_IFACE no existe"
fi

# --- 4. Eliminar overlay de la VM ---
if [ -f "$OVERLAY_IMG" ]; then
    echo "[+] Eliminando overlay $OVERLAY_IMG"
    rm -f "$OVERLAY_IMG"
else
    echo "[=] Overlay $OVERLAY_IMG no existe"
fi

echo "[OK] delete_vm.sh finalizado para $VM_NAME"