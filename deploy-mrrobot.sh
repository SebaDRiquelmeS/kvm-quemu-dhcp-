#!/bin/bash
# ============================================================
# Deploy Mr. Robot - Alta
# Uso: ./deploy-mrrobot.sh <ruta/al/mrrobot.qcow2>
# ============================================================
set -e

IMG="$(realpath "${1:-./images/mrrobot.sh.qcow2}")"
NAME="mrrobot"
NET="vulnhub_lab"

if [ ! -f "$IMG" ]; then
    echo "Uso: $0 <ruta/al/mrrobot.qcow2>"
    echo "Convierte primero: ./convert.sh mrRobot.ova mrrobot"
    exit 1
fi

echo "[*] Desplegando $NAME desde $IMG"

# ── Red ──
virsh net-info "$NET" 2>/dev/null || {
    echo "[*] Creando red $NET..."
    virsh net-define /dev/stdin <<'NET'
<network>
  <name>vulnhub_lab</name>
  <forward mode='nat'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp><range start='192.168.100.100' end='192.168.100.200'/></dhcp>
  </ip>
</network>
NET
    virsh net-start "$NET"
    virsh net-autostart "$NET"
}

# ── Firewall ──
BRIDGE=$(virsh net-dumpxml "$NET" | grep "bridge name" | grep -oP 'virbr\d+')
echo "[*] Configurando firewall ($BRIDGE)..."
sudo iptables -C FORWARD -i "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$BRIDGE" -j ACCEPT
sudo iptables -C FORWARD -o "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -o "$BRIDGE" -j ACCEPT
sudo iptables -C INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT
sudo iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE

# ── VM ──
virsh destroy "$NAME" 2>/dev/null || true
virsh undefine "$NAME" 2>/dev/null || true

virsh define /dev/stdin <<VMXML
<domain type='kvm'>
  <name>$NAME</name>
  <memory unit='MiB'>512</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$IMG'/>
      <target dev='sda' bus='sata'/>
    </disk>
    <interface type='network'>
      <source network='$NET'/>
      <model type='e1000'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
VMXML

virsh start "$NAME"
echo "[OK] $NAME desplegado. Esperando DHCP..."
sleep 60
virsh net-dhcp-leases "$NET" | grep "$NAME" && echo "[+] DHCP OK" || echo "[!] Revisa VNC: gvncviewer localhost:2"
