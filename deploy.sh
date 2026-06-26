#!/bin/bash
# ============================================================
# Deploy VulnHub VM con DHCP - Script genérico
# ============================================================
# Uso:
#   ./deploy.sh <nombre> <ruta/al/disk.qcow2> [opciones]
#
# Opciones:
#   --disk bus:dev    Tipo de disco (default: sata/sda)
#                     Ej: --disk ide:hda, --disk virtio:vda
#   --nic modelo      Modelo de NIC (default: e1000)
#                     Ej: --nic pcnet, --nic rtl8139
#   --mem MB          RAM en MB (default: 512)
#   --mac XX:XX:XX    MAC address (opcional)
#   --fix-grub        Corrige timeout=-1 en GRUB
#   --fix-modules     Corrige alias eth0 en modules.conf
#   --os redhat|debian  Tipo de SO para fixes (default: auto)
#
# Ejemplos:
#   ./deploy.sh myvm ./images/myvm.qcow2
#   ./deploy.sh kioptrix ./images/kioptrix.qcow2 --disk ide:hda --nic pcnet --mem 256 --fix-modules --os redhat
#   ./deploy.sh tr0ll ./images/tr0ll.qcow2 --fix-grub
# ============================================================
set -e

# ── Defaults ──
DISK_BUS="sata"
DISK_DEV="sda"
NIC_MODEL="e1000"
MEMORY=512
NET="vulnhub_lab"
SUBNET="192.168.100.0/24"
GATEWAY="192.168.100.1"
DHCP_START="192.168.100.100"
DHCP_END="192.168.100.200"
MAC=""
FIX_GRUB=false
FIX_MODULES=false
OS_TYPE="auto"
FIX_DHCP_HOSTNAME=""
VM_NAME=""

# ── Parse args ──
if [ $# -lt 2 ]; then
    echo "Uso: $0 <nombre> <ruta/al/disk.qcow2> [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --disk bus:dev     Tipo de disco (default: sata/sda)"
    echo "  --nic modelo       Modelo de NIC (default: e1000)"
    echo "  --mem MB           RAM en MB (default: 512)"
    echo "  --mac XX:XX:XX     MAC address"
    echo "  --fix-grub         Corrige GRUB timeout=-1"
    echo "  --fix-modules      Corrige alias eth0 en modules.conf + DHCP_HOSTNAME"
    echo "  --os redhat|debian Tipo de SO (default: auto-detect)"
    echo "  --network NAME     Nombre de la red (default: vulnhub_lab)"
    echo ""
    echo "Ejemplos:"
    echo "  $0 kioptrix ./images/kioptrix.qcow2 --disk ide:hda --nic pcnet --mem 256 --fix-modules --os redhat"
    echo "  $0 tr0ll ./images/tr0ll.qcow2 --fix-grub"
    echo "  $0 myvm ./images/myvm.qcow2"
    exit 1
fi

VM_NAME="$1"
IMG="$2"
shift 2

while [ $# -gt 0 ]; do
    case "$1" in
        --disk)   DISK_BUS="${2%%:*}"; DISK_DEV="${2##*:}"; shift 2 ;;
        --nic)    NIC_MODEL="$2"; shift 2 ;;
        --mem)    MEMORY="$2"; shift 2 ;;
        --mac)    MAC="$2"; shift 2 ;;
        --fix-grub)    FIX_GRUB=true; shift ;;
        --fix-modules) FIX_MODULES=true; shift ;;
        --os)     OS_TYPE="$2"; shift 2 ;;
        --network) NET="$2"; shift 2 ;;
        *) echo "Opcion desconocida: $1"; exit 1 ;;
    esac
done

if [ ! -f "$IMG" ]; then
    echo "Error: No existe $IMG"
    echo "Convierte primero: ./convert.sh <archivo.rar/.ova>"
    exit 1
fi

# ── Funciones ──
setup_network() {
    virsh net-info "$NET" 2>/dev/null && return
    echo "[*] Creando red $NET ($SUBNET)..."
    virsh net-define /dev/stdin <<NETXML
<network>
  <name>$NET</name>
  <forward mode='nat'/>
  <ip address='$GATEWAY' netmask='255.255.255.0'>
    <dhcp><range start='$DHCP_START' end='$DHCP_END'/></dhcp>
  </ip>
</network>
NETXML
    virsh net-start "$NET"
    virsh net-autostart "$NET"
}

setup_firewall() {
    local BRIDGE=$(virsh net-dumpxml "$NET" | grep "bridge name" | grep -oP 'virbr\d+')
    [ -z "$BRIDGE" ] && BRIDGE=virbr1
    echo "[*] Firewall ($BRIDGE)..."
    sudo iptables -C FORWARD -i "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$BRIDGE" -j ACCEPT
    sudo iptables -C FORWARD -o "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -o "$BRIDGE" -j ACCEPT
    sudo iptables -C FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT
    sudo iptables -C INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -i "$BRIDGE" -p udp --dport 67 -j ACCEPT
    sudo iptables -t nat -C POSTROUTING -s "$SUBNET" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s "$SUBNET" -j MASQUERADE
    sudo ufw allow in on "$BRIDGE" 2>/dev/null || true
}

auto_detect_os() {
    echo "[*] Detectando SO..."
    sudo modprobe nbd max_part=8 2>/dev/null || true
    
    # Buscar la particion root (tipo 83 Linux, la mas grande)
    sudo qemu-nbd --connect=/dev/nbd9 "$IMG" 2>/dev/null || return
    sleep 1
    
    local root_part=""
    for part in /dev/nbd9p*; do
        [ -b "$part" ] || continue
        sudo mount -o ro "$part" /mnt 2>/dev/null || continue
        if [ -f /mnt/etc/os-release ] || [ -f /mnt/etc/debian_version ] || [ -f /mnt/etc/redhat-release ]; then
            root_part="$part"
            sudo umount /mnt 2>/dev/null
            break
        fi
        sudo umount /mnt 2>/dev/null
    done
    
    if [ -n "$root_part" ]; then
        sudo mount "$root_part" /mnt 2>/dev/null
        if [ -f /mnt/etc/debian_version ]; then
            OS_TYPE="debian"
            echo "  -> Debian/Ubuntu"
        elif [ -f /mnt/etc/redhat-release ]; then
            OS_TYPE="redhat"
            echo "  -> Red Hat/CentOS ($(cat /mnt/etc/redhat-release))"
        fi
        # Detectar si tiene GRUB timeout=-1
        if $FIX_GRUB || sudo grep -q "timeout=-1\|set timeout=-1" /mnt/boot/grub/grub.cfg 2>/dev/null; then
            FIX_GRUB=true
            echo "  -> GRUB timeout=-1 detectado (se corregira)"
        fi
        sudo umount /mnt 2>/dev/null
    fi
    
    sudo qemu-nbd --disconnect /dev/nbd9 2>/dev/null
}

apply_fixes() {
    echo "[*] Aplicando fixes al disco..."
    sudo modprobe nbd max_part=8 2>/dev/null || true
    sudo qemu-nbd --connect=/dev/nbd8 "$IMG" 2>/dev/null || return
    sleep 1
    
    # Encontrar y montar particion root
    local mounted=false
    for part in /dev/nbd8p*; do
        [ -b "$part" ] || continue
        sudo mount "$part" /mnt 2>/dev/null || continue
        
        # ── Fix GRUB timeout ──
        if $FIX_GRUB; then
            for grub_cfg in /mnt/boot/grub/grub.cfg /mnt/boot/grub2/grub.cfg; do
                if [ -f "$grub_cfg" ]; then
                    echo "  -> GRUB: timeout=-1 -> timeout=3"
                    sudo sed -i 's/set timeout=-1/set timeout=3/' "$grub_cfg"
                    sudo sed -i 's/set timeout=.*/set timeout=3/' "$grub_cfg"
                fi
            done
            if [ -f /mnt/etc/default/grub ]; then
                sudo sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /mnt/etc/default/grub 2>/dev/null || true
                grep -q GRUB_TIMEOUT /mnt/etc/default/grub 2>/dev/null || echo "GRUB_TIMEOUT=3" | sudo tee -a /mnt/etc/default/grub >/dev/null
            fi
        fi
        
        # ── Fix modules + DHCP para Red Hat ──
        if $FIX_MODULES || [ "$OS_TYPE" = "redhat" ]; then
            if [ -f /mnt/etc/modules.conf ]; then
                echo "  -> modules.conf: alias eth0 -> $NIC_MODEL"
                # Detectar nombre de modulo correcto segun NIC
                local mod_name="$NIC_MODEL"
                case "$NIC_MODEL" in
                    pcnet) mod_name="pcnet32" ;;
                    rtl8139) mod_name="8139too" ;;
                    ne2k_pci) mod_name="ne2k-pci" ;;
                esac
                sudo sed -i "s/alias eth0.*/alias eth0 $mod_name/" /mnt/etc/modules.conf
            fi
            if [ -f /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
                grep -q DHCP_HOSTNAME /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null || \
                    echo "DHCP_HOSTNAME=${VM_NAME}" | sudo tee -a /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 >/dev/null
                # Asegurar ONBOOT=yes y BOOTPROTO=dhcp
                sudo sed -i 's/ONBOOT=.*/ONBOOT=yes/' /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
                sudo sed -i 's/BOOTPROTO=.*/BOOTPROTO=dhcp/' /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
            fi
            sudo rm -f /mnt/etc/dhcpc/dhcpcd-eth0.* 2>/dev/null
        fi
        
        # ── Fix Debian/Ubuntu interfaces ──
        if [ "$OS_TYPE" = "debian" ]; then
            if [ -f /mnt/etc/network/interfaces ]; then
                if ! grep -q "iface eth0 inet dhcp" /mnt/etc/network/interfaces 2>/dev/null; then
                    echo "  -> Agregando DHCP a interfaces"
                    echo "auto eth0" | sudo tee -a /mnt/etc/network/interfaces >/dev/null
                    echo "iface eth0 inet dhcp" | sudo tee -a /mnt/etc/network/interfaces >/dev/null
                fi
            fi
            # Limpiar udev persistent rules
            sudo rm -f /mnt/etc/udev/rules.d/70-persistent-net.rules 2>/dev/null
        fi
        
        mounted=true
        sudo umount /mnt 2>/dev/null
        break
    done
    
    sudo qemu-nbd --disconnect /dev/nbd8 2>/dev/null
    $mounted || echo "  [!] No se pudo montar la particion root (se omite fixes de disco)"
}

# ── MAIN ──
echo "========================================"
echo "  Deploy: $VM_NAME"
echo "  Disco:  $IMG"
echo "  RAM:    ${MEMORY}MB"
echo "  Disk:   $DISK_BUS / $DISK_DEV"
echo "  NIC:    $NIC_MODEL"
echo "========================================"

setup_network
setup_firewall

if [ "$OS_TYPE" = "auto" ]; then
    auto_detect_os
fi

apply_fixes

# ── Definir VM ──
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" 2>/dev/null || true

MAC_XML=""
[ -n "$MAC" ] && MAC_XML="<mac address='$MAC'/>"

echo "[*] Definiendo VM..."
virsh define /dev/stdin <<VMXML
<domain type='kvm'>
  <name>$VM_NAME</name>
  <memory unit='MiB'>$MEMORY</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$IMG'/>
      <target dev='$DISK_DEV' bus='$DISK_BUS'/>
    </disk>
    <interface type='network'>
      $MAC_XML
      <source network='$NET'/>
      <model type='$NIC_MODEL'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
VMXML

virsh start "$VM_NAME"

echo ""
echo "[OK] $VM_NAME desplegado. Esperando DHCP (60s)..."
sleep 60

IP=$(virsh net-dhcp-leases "$NET" 2>/dev/null | grep -i "$VM_NAME" | awk '{print $5}' | head -1)
if [ -n "$IP" ]; then
    echo "[+] DHCP OK - IP: $IP"
else
    echo "[!] Sin DHCP aun. Revisa:"
    echo "    gvncviewer localhost:\$(virsh domdisplay $VM_NAME | grep -oP ':\d+')"
    echo "    virsh console $VM_NAME"
fi
