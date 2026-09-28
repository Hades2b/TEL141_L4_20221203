#!/bin/bash
# create_vm.sh
# Uso: bash -s -- <VM_NAME> <OVS_BRIDGE> <VLAN_ID> <VNC_PORT>
# Ejemplo: bash -s -- vm1_vlan100 br-int 100 1

set -euo pipefail

# --- Parámetros ---
VM_NAME=${1:?"Error: VM_NAME no proporcionado."}
OVS_BRIDGE=${2:?"Error: OVS_BRIDGE no proporcionado."}
VLAN_ID=${3:?"Error: VLAN_ID no proporcionado."}
VNC_PORT=${4:?"Error: VNC_PORT no proporcionado."}

IMG_DIR="$HOME/images"
BASE_IMG="${IMG_DIR}/cirros-0.5.1-x86_64-disk.img"
BASE_URL="http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img"
OVERLAY_IMG="${IMG_DIR}/${VM_NAME}.qcow2"
TAP_IFACE="${VM_NAME}_tap"
PID_FILE="/tmp/${VM_NAME}.pid"
VNC_QEMU=$VNC_PORT
VM_ID="${VM_NAME#vm}"
VM_ID="${VM_ID%%_vlan*}"

MAC_ADDR=$(printf "22:12:03:%02x:%02x:%02x" $(( VLAN_ID >> 8 )) $(( VLAN_ID & 255 )) "$VM_ID")

# --- Validaciones ---
if ! sudo ovs-vsctl br-exists "$OVS_BRIDGE" 2>/dev/null; then
    echo "Error: El bridge $OVS_BRIDGE no existe. Ejecute init_worker.sh primero."
    exit 1
fi

echo "[i] VM: $VM_NAME  | VLAN: $VLAN_ID | VNC: 0.0.0.0:$VNC_QEMU | MAC: $MAC_ADDR"

# --- 1. Preparar imagen base ---
mkdir -p "$IMG_DIR"

if [ ! -f "$BASE_IMG" ]; then
    echo "[+] Imagen base no encontrada. Descargando CirrOS..."
    if wget -q -O "$BASE_IMG" "$BASE_URL"; then
        echo "[OK] Descarga completada"
    else
        echo "[ERROR] No se pudo descargar $BASE_URL"
        exit 1
    fi
else
    echo "[=] Imagen base ya existe: $BASE_IMG"
fi

# --- 2. Limpieza previa ---
echo "[+] Limpiando restos previos de la VM..."
# Detener QEMU si está corriendo
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(sudo cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && sudo kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[+] Deteniendo QEMU previo (PID $OLD_PID)"
        sudo kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    sudo rm -f "$PID_FILE"
fi
# Eliminar TAP del OVS y del sistema
sudo ovs-vsctl --if-exists del-port "$OVS_BRIDGE" "$TAP_IFACE" || true
sudo ip link del "$TAP_IFACE" 2>/dev/null || true
# Eliminar overlay previo
[ -f "$OVERLAY_IMG" ] && rm -f "$OVERLAY_IMG"

# --- 3. Crear overlay QCOW2 ---
echo "[+] Creando overlay $OVERLAY_IMG sobre imagen base"
qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$OVERLAY_IMG" >/dev/null

# --- 4. Crear interfaz TAP ---
echo "[+] Creando interfaz TAP $TAP_IFACE"
sudo ip tuntap add mode tap name "$TAP_IFACE"

# --- 5. Lanzar QEMU ---
echo "[+] Lanzando QEMU en background (VNC :$VNC_QEMU)"
sudo qemu-system-x86_64 \
    -enable-kvm \
    -vnc 0.0.0.0:${VNC_QEMU} \
    -netdev tap,id=tap_${VLAN_ID},ifname=${TAP_IFACE},script=no,downscript=no \
    -device e1000,netdev=tap_${VLAN_ID},mac=${MAC_ADDR} \
    -daemonize \
    -pidfile "$PID_FILE" \
    "$OVERLAY_IMG"

sleep 1

# Verificar proceso QEMU
if [ -f "$PID_FILE" ] && sudo kill -0 "$(sudo cat $PID_FILE)" 2>/dev/null; then
    echo "[=] QEMU corriendo con PID $(sudo cat $PID_FILE)"
else
    echo "[!] Error: QEMU no arrancó correctamente."
    exit 1
fi

# --- 6. Conectar TAP a OVS con tag de VLAN ---
echo "[+] Conectando $TAP_IFACE a $OVS_BRIDGE con tag $VLAN_ID"
sudo ovs-vsctl add-port "$OVS_BRIDGE" "$TAP_IFACE" tag="$VLAN_ID"
sudo ip link set dev "$TAP_IFACE" up

echo "[OK] create_vm.sh finalizado. VM $VM_NAME disponible por VNC en el puerto $((5900 + VNC_QEMU))"