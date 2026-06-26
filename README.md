# KVM + QEMU - Laboratorio de Pentesting con DHCP funcional

Script de despliegue automático para máquinas VulnHub con DHCP 100% funcional.

## Problemas que soluciona

| Problema | Causa | Solución |
|----------|-------|----------|
| VMs no bootean | QEMU 11.x `-blockdev driver=file` no funciona con SeaBIOS | `<driver type='qcow2'/>` + `<disk type='file'>` |
| Sin DHCP | UFW bloquea tráfico en FORWARD | `ufw allow in on virbr1` + reglas iptables |
| Tr0ll atascado en GRUB | `timeout=-1` | Cambiar a `timeout=3` en grub.cfg |
| Kioptrix sin red | `alias eth0 e1000` pero NIC es `pcnet` | Revertir a `alias eth0 pcnet32` |
| NIC invisible | Machine `q35` esconde NIC tras PCIe bridges | Usar `machine='pc'` (i440FX) |
| dhcpcd sin hostname | `DHCP_HOSTNAME` vacío | Agregar en ifcfg-eth0 |

## Requisitos

```bash
sudo pacman -S libvirt qemu-base qemu-nbd
sudo usermod -aG libvirt $USER
```

## Uso

```bash
# 1. Clonar
git clone <repo>
cd kvm-quemu-dhcp-

# 2. Poner las imagenes .qcow2 en ./images/ o .vmdk en cualquier lado
mkdir -p images

# 3. Desplegar
./deploy.sh
```

## Estructura de las VMs

| VM | IP (DHCP) | Dificultad | Disco | NIC | Machine |
|----|-----------|------------|-------|-----|---------|
| kioptrix | 192.168.100.x | Baja | IDE (hda) | pcnet | pc |
| tr0ll | 192.168.100.x | Media | SATA (sda) | e1000 | pc |
| mrrobot | 192.168.100.x | Alta | SATA (sda) | e1000 | pc |

## Comandos útiles post-deploy

```bash
# Ver IPs
virsh net-dhcp-leases vulnhub_lab

# Consola
virsh console kioptrix

# VNC
gvncviewer localhost:0   # kioptrix
gvncviewer localhost:1   # tr0ll
gvncviewer localhost:2   # mrrobot

# Escaneo
nmap -sC -sV -p- 192.168.100.0/24
```
