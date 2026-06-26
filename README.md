# KVM + QEMU + Terraform → Lab de Pentesting con DHCP funcional

Despliegue automatizado de 3 máquinas VulnHub (Baja, Media, Alta) con red DHCP 100% funcional.

## Tabla de fixes incluidos

| # | Problema | Causa | Solución |
|---|----------|-------|----------|
| 1 | VMs no bootean | QEMU 11.x `-blockdev driver=file` roto con SeaBIOS | `<disk type='file'>` + `<driver type='qcow2'/>` |
| 2 | Sin DHCP | UFW bloquea FORWARD | `ufw allow in on virbr1` + iptables |
| 3 | Tr0ll atascado en GRUB | `timeout=-1` (espera infinita) | `set timeout=3` en grub.cfg |
| 4 | Kioptrix sin red | `alias eth0 e1000` pero NIC es `pcnet` | `alias eth0 pcnet32` + NIC `pcnet` |
| 5 | NIC invisible | Machine `q35` esconde NIC tras PCIe bridges | `machine='pc'` (i440FX) |
| 6 | dhcpcd sin hostname | `DHCP_HOSTNAME` vacío en Kioptrix | Agregar a `ifcfg-eth0` |

## Requisitos

```bash
# Arch Linux
sudo pacman -S terraform libvirt qemu-base qemu-nbd

# Tu usuario en grupo libvirt
sudo usermod -aG libvirt $USER
# Cerrá sesión y volvé a entrar
```

## Estructura del proyecto

```
.
├── main.tf          # Terraform: red + VMs + fixes
├── deploy.sh        # Script alternativo (sin Terraform)
├── images/          # Poner aqui los .qcow2
│   ├── kioptrix.qcow2
│   ├── tr0ll.qcow2
│   └── mrrobot.qcow2
└── README.md
```

## Uso rápido

```bash
# 1. Clonar
git clone https://github.com/SebaDRiquelmeS/kvm-quemu-dhcp-.git
cd kvm-quemu-dhcp-

# 2. Meter las imagenes .qcow2 en ./images/
mkdir -p images
# cp /ruta/a/tus/*.qcow2 images/

# 3. Desplegar
terraform init
terraform apply
```

## Conversión de .vmdk/.ova a .qcow2

```bash
# .rar (VMware)
bsdtar -xvf maquina.rar
qemu-img convert -f vmdk -O qcow2 maquina.vmdk images/maquina.qcow2

# .ova (VirtualBox/VMware)
bsdtar -xvf maquina.ova
qemu-img convert -f vmdk -O qcow2 *-disk1.vmdk images/maquina.qcow2
```

## VMs desplegadas

| VM | IP (DHCP) | Disco | NIC | Machine |
|----|-----------|-------|-----|---------|
| kioptrix | 192.168.100.x | IDE (hda) | pcnet | pc |
| tr0ll | 192.168.100.x | SATA (sda) | e1000 | pc |
| mrrobot | 192.168.100.x | SATA (sda) | e1000 | pc |

## Comandos post-deploy

```bash
# Ver IPs asignadas
virsh net-dhcp-leases vulnhub_lab

# VNC (si no tenés virt-viewer)
gvncviewer localhost:0   # kioptrix
gvncviewer localhost:1   # tr0ll
gvncviewer localhost:2   # mrrobot

# Consola serial
virsh console kioptrix

# Escaneo inicial
nmap -sC -sV -p- 192.168.100.0/24
```

---

## Convertir tus propias máquinas VulnHub

```bash
./convert.sh ~/Downloads/Kioptrix_Level_1.rar kioptrix
./convert.sh ~/Downloads/Tr0ll.rar tr0ll
./convert.sh ~/Downloads/mrRobot.ova mrrobot
```

Luego `terraform apply` y listo.
