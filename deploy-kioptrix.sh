#!/bin/bash
# ============================================================
# Deploy Kioptrix Level 1 - Baja
# Uso: ./deploy-kioptrix.sh <ruta/al/kioptrix.qcow2>
# ============================================================
set -e

IMG="$(realpath "${1:-./images/kioptrix.sh.qcow2}")"
NAME="kioptrix"
NET="vulnhub_lab"

if [ ! -f "$IMG" ]; then
    echo "Uso: $0 <ruta/al/kioptrix.qcow2>"
    echo "Convierte primero: ./convert.sh Kioptrix_Level_1.rar kioptrix"
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
sudo ufw allow in on "$BRIDGE" 2>/dev/null || true
sudo iptables -C FORWARD -i "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$BRIDGE" -j ACCEPT
sudo iptables -C FORWARD -o "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -o "$BRIDGE" -j ACCEPT
sudo iptables -C INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT
sudo iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE

# ── Fixes en disco ──
echo "[*] Aplicando fixes (modulos + DHCP_HOSTNAME)..."
sudo modprobe nbd max_part=8 2>/dev/null || true
sudo qemu-nbd --connect=/dev/nbd0 "$IMG" 2>/dev/null
sleep 1
sudo mount /dev/nbd0p5 /mnt 2>/dev/null && {
    if [ -f /mnt/etc/modules.conf ]; then
        sudo sed -i 's/alias eth0.*/alias eth0 pcnet32/' /mnt/etc/modules.conf
    fi
    if [ -f /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
        grep -q DHCP_HOSTNAME /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null || \
            echo "DHCP_HOSTNAME=kioptrix.level1" | sudo tee -a /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 >/dev/null
    fi
    sudo rm -f /mnt/etc/dhcpc/dhcpcd-eth0.* 2>/dev/null
    sudo umount /mnt
}
sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null

# ── VM ──
virsh destroy "$NAME" 2>/dev/null || true
virsh undefine "$NAME" 2>/dev/null || true

virsh define /dev/stdin <<VMXML
<domain type='kvm'>
  <name>$NAME</name>
  <memory unit='MiB'>256</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$IMG'/>
      <target dev='hda' bus='ide'/>
    </disk>
    <interface type='network'>
      <mac address='00:0c:29:7c:3a:16'/>
      <source network='$NET'/>
      <model type='pcnet'/>
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
virsh net-dhcp-leases "$NET" | grep "$NAME" && echo "[+] DHCP OK" || echo "[!] Revisa VNC: gvncviewer localhost:0"
