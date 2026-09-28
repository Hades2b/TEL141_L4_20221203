#!/bin/bash
# init_master.sh
# Uso: bash -s -- <interfaz1> [<interfaz2> ...]
# Ejemplo: bash -s -- ens4

set -euo pipefail

BRIDGE="br-int"

# --- Validación de parámetros ---
if [ "$#" -lt 1 ]; then
    echo "Ejecute con interfaces de red como parámetros."
    exit 1
fi

# --- 1. Crear bridge OVS 'br-int' si no existe ---
if ! sudo ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    echo "[+] Creando bridge OVS $BRIDGE"
    sudo ovs-vsctl add-br "$BRIDGE"
else
    echo "[=] Bridge OVS $BRIDGE ya existe"
fi

# --- 2. Conectar interfaces provistas al bridge ---
for IFACE in "$@"; do
    if [ "$IFACE" = "ens3" ]; then
        echo "[=] Omitiendo interfaz $IFACE (red de gestión)"
        continue
    fi
    
    if ip link show "$IFACE" >/dev/null 2>&1; then
        echo "[+] Agregando $IFACE a $BRIDGE"
        sudo ovs-vsctl --may-exist add-port "$BRIDGE" "$IFACE"
        sudo ip link set dev "$IFACE" up
    else
        echo "[!] La interfaz $IFACE no existe. Se omite."
    fi
done

# --- 3. Activar IPv4 forwarding ---
echo "[+] Activando IPv4 forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- 4. Política por defecto de FORWARD: DROP ---
echo "[+] Estableciendo política FORWARD a DROP"
sudo iptables -P FORWARD DROP
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "[OK] init_master.sh finalizado correctamente."