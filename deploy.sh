#!/bin/bash
set -e

# ============================================================
# Pentest Lab Auto-Deploy - KVM + QEMU + DHCP funcional
# ============================================================
# Soluciona todos los problemas conocidos:
#   1. Bug -blockdev driver=file en QEMU 11.x → usa type='qcow2'
#   2. UFW bloquea trafico DHCP → agrega reglas
#   3. GRUB timeout=-1 en Tr0ll → timeout=3
#   4. Module alias pcnet32 vs e1000 en Kioptrix → pcnet32
#   5. Machine type q35 esconde NIC → pc (i440FX)
#   6. DHCP_HOSTNAME faltante en Kioptrix → se agrega
# ============================================================

LAB_DIR="$(dirname "$0")"
IMAGES_DIR="${LAB_DIR}/images"
TMP_DIR="${LAB_DIR}/tmp"

# Colores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

# ============================================================
# 0. Verificar dependencias
# ============================================================
info "Verificando dependencias..."
for cmd in virsh qemu-img qemu-nbd; do
    command -v $cmd >/dev/null || error "Falta $cmd. Instalalo: sudo pacman -S libvirt qemu-base"
done

# Verificar grupo libvirt
groups | grep -q libvirt || warn "Usuario no esta en grupo libvirt. Ejecuta: sudo usermod -aG libvirt $USER"

# ============================================================
# 1. Preparar imagenes
# ============================================================
info "Preparando imagenes QCOW2..."
mkdir -p "${IMAGES_DIR}" "${TMP_DIR}"

# Funcion para convertir VMDK/OVA a QCOW2
convert_image() {
    local src="$1" dst="$2"
    if [ -f "$dst" ]; then
        info "  $dst ya existe, saltando..."
        return
    fi
    info "  Convirtiendo $(basename "$src")..."
    qemu-img convert -f vmdk -O qcow2 "$src" "$dst"
}

# Si no existen las imagenes, busca en directorios comunes
if [ ! -f "${IMAGES_DIR}/kioptrix.qcow2" ]; then
    SRC=$(find / -name "Kioptrix*.vmdk" 2>/dev/null | head -1)
    [ -n "$SRC" ] && convert_image "$SRC" "${IMAGES_DIR}/kioptrix.qcow2"
fi
if [ ! -f "${IMAGES_DIR}/tr0ll.qcow2" ]; then
    SRC=$(find / -name "Tr0ll*.vmdk" 2>/dev/null | head -1)
    [ -n "$SRC" ] && convert_image "$SRC" "${IMAGES_DIR}/tr0ll.qcow2"
fi
if [ ! -f "${IMAGES_DIR}/mrrobot.qcow2" ]; then
    SRC=$(find / -name "mrRobot-disk1.vmdk" 2>/dev/null | head -1)
    [ -n "$SRC" ] && convert_image "$SRC" "${IMAGES_DIR}/mrrobot.qcow2"
fi

# ============================================================
# 2. Fixes en las imagenes de disco
# ============================================================
fix_disk_images() {
    info "Aplicando fixes a las imagenes de disco..."

    # Fix Kioptrix: module alias + DHCP_HOSTNAME
    if [ -f "${IMAGES_DIR}/kioptrix.qcow2" ]; then
        info "  Fix Kioptrix..."
        sudo -S qemu-nbd --connect=/dev/nbd0 "${IMAGES_DIR}/kioptrix.qcow2" 2>/dev/null
        sleep 1
        sudo mount /dev/nbd0p5 "${TMP_DIR}" 2>/dev/null
        if [ -f "${TMP_DIR}/etc/modules.conf" ]; then
            sudo sed -i 's/alias eth0.*/alias eth0 pcnet32/' "${TMP_DIR}/etc/modules.conf"
            grep -q "DHCP_HOSTNAME" "${TMP_DIR}/etc/sysconfig/network-scripts/ifcfg-eth0" 2>/dev/null || \
                echo "DHCP_HOSTNAME=kioptrix.level1" | sudo tee -a "${TMP_DIR}/etc/sysconfig/network-scripts/ifcfg-eth0" >/dev/null
        fi
        sudo umount "${TMP_DIR}" 2>/dev/null
        sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null
    fi

    # Fix Tr0ll: GRUB timeout
    if [ -f "${IMAGES_DIR}/tr0ll.qcow2" ]; then
        info "  Fix Tr0ll GRUB timeout..."
        sudo -S qemu-nbd --connect=/dev/nbd1 "${IMAGES_DIR}/tr0ll.qcow2" 2>/dev/null
        sleep 1
        sudo mount /dev/nbd1p1 "${TMP_DIR}" 2>/dev/null
        if [ -f "${TMP_DIR}/boot/grub/grub.cfg" ]; then
            sudo sed -i 's/set timeout=.*/set timeout=3/' "${TMP_DIR}/boot/grub/grub.cfg"
        fi
        sudo umount "${TMP_DIR}" 2>/dev/null
        sudo qemu-nbd --disconnect /dev/nbd1 2>/dev/null
    fi
}
fix_disk_images

# ============================================================
# 3. Red aislada + reglas UFW
# ============================================================
info "Configurando red vulnhub_lab..."
virsh net-destroy vulnhub_lab 2>/dev/null || true
virsh net-undefine vulnhub_lab 2>/dev/null || true

cat > "${TMP_DIR}/net.xml" << 'NETXML'
<network>
  <name>vulnhub_lab</name>
  <forward mode='nat'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.200'/>
    </dhcp>
  </ip>
</network>
NETXML

virsh net-define "${TMP_DIR}/net.xml"
virsh net-start vulnhub_lab
virsh net-autostart vulnhub_lab

# Reglas UFW para permitir trafico DHCP
info "Configurando firewall..."
if command -v ufw >/dev/null 2>&1; then
    sudo -S ufw allow in on virbr1 2>/dev/null || true
    sudo -S ufw route allow in on virbr1 out on virbr1 2>/dev/null || true
fi

# Reglas iptables adicionales
BRIDGE=$(virsh net-dumpxml vulnhub_lab | grep "bridge name" | grep -oP "virbr\d+")
if [ -n "$BRIDGE" ]; then
    sudo -S iptables -I FORWARD -i "$BRIDGE" -j ACCEPT 2>/dev/null || true
    sudo -S iptables -I FORWARD -o "$BRIDGE" -j ACCEPT 2>/dev/null || true
    sudo -S iptables -I FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT 2>/dev/null || true
    sudo -S iptables -I INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT 2>/dev/null || true
    sudo -S iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE 2>/dev/null || true
fi

# ============================================================
# 4. Definir VMs con XML correcto
# ============================================================
info "Definiendo VMs..."

define_vm() {
    local name="$1" machine="$2" mem="$3" disk_bus="$4" disk_dev="$5" nic="$6" mac="$7" disk_path="$8"

    virsh destroy "$name" 2>/dev/null || true
    virsh undefine "$name" 2>/dev/null || true

    local mac_xml=""
    [ -n "$mac" ] && mac_xml="<mac address='$mac'/>"

    # Fix: usar type='qcow2' para evitar bug -blockdev de QEMU 11.x
    # Fix: usar machine='pc' para que la NIC PCI sea visible directamente
    virsh define /dev/stdin << VMXML
<domain type='kvm'>
  <name>$name</name>
  <memory unit='MiB'>$mem</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os>
    <type arch='x86_64' machine='$machine'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$disk_path'/>
      <target dev='$disk_dev' bus='$disk_bus'/>
    </disk>
    <interface type='network'>
      $mac_xml
      <source network='vulnhub_lab'/>
      <model type='$nic'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
VMXML
    virsh start "$name"
    info "  $name: listo"
}

# Kioptrix: IDE + pcnet (module=pcnet32), machine=pc
define_vm "kioptrix"  "pc"  256 "ide"  "hda" "pcnet"  "00:0c:29:7c:3a:16" "${IMAGES_DIR}/kioptrix.qcow2"

# Tr0ll: SATA + e1000, machine=pc
define_vm "tr0ll"     "pc"  512 "sata" "sda" "e1000" "00:0c:29:39:e9:62" "${IMAGES_DIR}/tr0ll.qcow2"

# MrRobot: SATA + e1000, machine=pc
define_vm "mrrobot"   "pc"  512 "sata" "sda" "e1000" ""                 "${IMAGES_DIR}/mrrobot.qcow2"

# ============================================================
# 5. Esperar y verificar DHCP
# ============================================================
info "Esperando que las VMs obtengan DHCP (90s)..."
sleep 90

echo ""
info "=== DHCP Leases ==="
virsh net-dhcp-leases vulnhub_lab

echo ""
info "=== VMs corriendo ==="
virsh list

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Laboratorio listo!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Kioptrix  (Baja):  http://192.168.100.x"
echo "  Tr0ll     (Media): http://192.168.100.x"
echo "  Mr. Robot (Alta):  http://192.168.100.x"
echo ""
echo "  Comandos utiles:"
echo "    virsh console <nombre>"
echo "    gvncviewer localhost:<N>"
echo "    virsh net-dhcp-leases vulnhub_lab"
echo "    nmap -sC -sV -p- <IP>"
