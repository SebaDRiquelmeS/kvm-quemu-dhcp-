# ============================================================
# Laboratorio de Pentesting - KVM + Terraform + DHCP
# ============================================================
# Despliegue 100% automatizado para 3 maquinas VulnHub:
#   - Kioptrix Level 1 (Baja)
#   - Tr0ll (Media)
#   - Mr. Robot (Alta)
#
# FIXES incluidos:
#   1. QEMU 11.x -blockdev bug → <disk type='file'> + type='qcow2'
#   2. UFW bloquea DHCP → reglas iptables/ufw en post-deploy
#   3. GRUB timeout=-1 (Tr0ll) → timeout=3
#   4. Module alias e1000 vs pcnet (Kioptrix) → pcnet32
#   5. Machine q35 esconde NIC → pc (i440FX)
#   6. dhcpcd sin hostname (Kioptrix) → DHCP_HOSTNAME en ifcfg
# ============================================================

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# ──────────────────────────────────────────
# Red NAT aislada 192.168.100.0/24 + DHCP
# ──────────────────────────────────────────
resource "libvirt_network" "lab_net" {
  name      = "vulnhub_lab"
  autostart = true

  forward {
    mode = "nat"
  }

  ips {
    address = "192.168.100.1"
    netmask = "255.255.255.0"
    dhcp {
      ranges {
        start = "192.168.100.100"
        end   = "192.168.100.200"
      }
    }
  }
}

# ──────────────────────────────────────────
# VMs definidas via local-exec
# (evita bug -blockdev driver=file en QEMU 11)
# ──────────────────────────────────────────
resource "terraform_data" "deploy_vms" {
  depends_on = [libvirt_network.lab_net]

  provisioner "local-exec" {
    command = <<-DEPLOY
      set -e
      NET_NAME="${libvirt_network.lab_net.name}"
      IMG_DIR="${path.module}/images"

      echo "[*] Definiendo VMs con XML corregido..."

      # ── Kioptrix (Baja) ──
      virsh destroy kioptrix 2>/dev/null || true
      virsh undefine kioptrix 2>/dev/null || true
      virsh define /dev/stdin <<'XML'
<domain type='kvm'>
  <name>kioptrix</name>
  <memory unit='MiB'>256</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${IMG_DIR}/kioptrix.qcow2'/>
      <target dev='hda' bus='ide'/>
    </disk>
    <interface type='network'>
      <mac address='00:0c:29:7c:3a:16'/>
      <source network='${NET_NAME}'/>
      <model type='pcnet'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
XML
      virsh start kioptrix
      echo "  [OK] kioptrix"

      # ── Tr0ll (Media) ──
      virsh destroy tr0ll 2>/dev/null || true
      virsh undefine tr0ll 2>/dev/null || true
      virsh define /dev/stdin <<'XML'
<domain type='kvm'>
  <name>tr0ll</name>
  <memory unit='MiB'>512</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${IMG_DIR}/tr0ll.qcow2'/>
      <target dev='sda' bus='sata'/>
    </disk>
    <interface type='network'>
      <mac address='00:0c:29:39:e9:62'/>
      <source network='${NET_NAME}'/>
      <model type='e1000'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
XML
      virsh start tr0ll
      echo "  [OK] tr0ll"

      # ── Mr. Robot (Alta) ──
      virsh destroy mrrobot 2>/dev/null || true
      virsh undefine mrrobot 2>/dev/null || true
      virsh define /dev/stdin <<'XML'
<domain type='kvm'>
  <name>mrrobot</name>
  <memory unit='MiB'>512</memory>
  <vcpu>1</vcpu>
  <cpu mode='host-passthrough'/>
  <os><type arch='x86_64' machine='pc'>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${IMG_DIR}/mrrobot.qcow2'/>
      <target dev='sda' bus='sata'/>
    </disk>
    <interface type='network'>
      <source network='${NET_NAME}'/>
      <model type='e1000'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
  </devices>
</domain>
XML
      virsh start mrrobot
      echo "  [OK] mrrobot"

      echo "[*] Todas las VMs desplegadas"
    DEPLOY
  }

  # ── Fix UFW + iptables para DHCP ──
  provisioner "local-exec" {
    command = <<-FIREWALL
      BRIDGE=$(virsh net-dumpxml vulnhub_lab 2>/dev/null | grep "bridge name" | grep -oP 'virbr\d+')
      if [ -z "$BRIDGE" ]; then BRIDGE=virbr1; fi

      echo "[*] Configurando firewall para $BRIDGE..."

      sudo ufw allow in on $BRIDGE 2>/dev/null || true
      sudo ufw route allow in on $BRIDGE out on $BRIDGE 2>/dev/null || true

      sudo iptables -I FORWARD -i $BRIDGE -j ACCEPT 2>/dev/null || true
      sudo iptables -I FORWARD -o $BRIDGE -j ACCEPT 2>/dev/null || true
      sudo iptables -I FORWARD -i $BRIDGE -o $BRIDGE -j ACCEPT 2>/dev/null || true
      sudo iptables -I INPUT -i $BRIDGE -p udp --dport 67 -j ACCEPT 2>/dev/null || true
      sudo iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -j MASQUERADE 2>/dev/null || \
        sudo iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE 2>/dev/null || true

      echo "[*] Firewall configurado"
    FIREWALL
  }
}

# ──────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────
output "network" {
  value = {
    name    = "vulnhub_lab"
    subnet  = "192.168.100.0/24"
    gateway = "192.168.100.1"
    dhcp    = "192.168.100.100 - 200"
  }
}

output "vms" {
  value = {
    kioptrix = "Baja  - IDE/pcnet  - machine=pc"
    tr0ll    = "Media - SATA/e1000 - machine=pc"
    mrrobot  = "Alta  - SATA/e1000 - machine=pc"
  }
}

output "instrucciones" {
  value = <<-EOF

    Laboratorio desplegado!

    Ver IPs:
      virsh net-dhcp-leases vulnhub_lab

    Consola:
      virsh console kioptrix

    VNC:
      gvncviewer localhost:0  (kioptrix)
      gvncviewer localhost:1  (tr0ll)
      gvncviewer localhost:2  (mrrobot)

    Pentest:
      nmap -sC -sV -p- 192.168.100.0/24
  EOF
}

# ──────────────────────────────────────────
# Script de fixes pre-deploy (discos)
# ──────────────────────────────────────────
resource "terraform_data" "fix_disks" {
  provisioner "local-exec" {
    command = <<-FIXDISKS
      IMG="${path.module}/images"

      echo "[*] Aplicando fixes a imagenes de disco..."

      fix_kioptrix() {
        if [ ! -f "$IMG/kioptrix.qcow2" ]; then return; fi
        echo "  [*] Fix Kioptrix (modulos + DHCP_HOSTNAME)..."
        sudo modprobe nbd max_part=8 2>/dev/null || true
        sudo qemu-nbd --connect=/dev/nbd0 "$IMG/kioptrix.qcow2" 2>/dev/null || return
        sleep 1
        sudo mount /dev/nbd0p5 /mnt 2>/dev/null || return
        if [ -f /mnt/etc/modules.conf ]; then
          sudo sed -i 's/alias eth0.*/alias eth0 pcnet32/' /mnt/etc/modules.conf
        fi
        if [ -f /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
          grep -q DHCP_HOSTNAME /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null || \
            echo "DHCP_HOSTNAME=kioptrix.level1" | sudo tee -a /mnt/etc/sysconfig/network-scripts/ifcfg-eth0 >/dev/null
        fi
        sudo rm -f /mnt/etc/dhcpc/dhcpcd-eth0.* 2>/dev/null
        sudo umount /mnt 2>/dev/null
        sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null
        echo "  [OK] Kioptrix"
      }

      fix_tr0ll() {
        if [ ! -f "$IMG/tr0ll.qcow2" ]; then return; fi
        echo "  [*] Fix Tr0ll (GRUB timeout=3)..."
        sudo modprobe nbd max_part=8 2>/dev/null || true
        sudo qemu-nbd --connect=/dev/nbd1 "$IMG/tr0ll.qcow2" 2>/dev/null || return
        sleep 1
        sudo mount /dev/nbd1p1 /mnt 2>/dev/null || return
        if [ -f /mnt/boot/grub/grub.cfg ]; then
          sudo sed -i 's/set timeout=.*/set timeout=3/' /mnt/boot/grub/grub.cfg
        fi
        sudo umount /mnt 2>/dev/null
        sudo qemu-nbd --disconnect /dev/nbd1 2>/dev/null
        echo "  [OK] Tr0ll"
      }

      fix_kioptrix
      fix_tr0ll
      echo "[*] Fixes completados"
    FIXDISKS
  }

  depends_on = []
}
