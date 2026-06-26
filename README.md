# VulnHub Lab — KVM + QEMU + DHCP automático

Despliega cualquier máquina VulnHub con DHCP funcional en un solo comando.

## Instalación (primera vez)

```bash
git clone git@github.com:SebaDRiquelmeS/kvm-quemu-dhcp-.git
cd kvm-quemu-dhcp-
./install.sh
```

`install.sh` instala libvirt, qemu, módulos del kernel, grupo libvirt, y deja todo listo.

## Uso

```bash
# 1. Convertir imagen de VulnHub
./convert.sh ~/Downloads/mi-maquina.ova mi-maquina

# 2. Desplegar
./deploy.sh mi-maquina ./images/mi-maquina.qcow2
```

## Opciones de deploy.sh

```
--disk  ide:hda     Disco IDE (máquinas viejas, Red Hat)
--disk  sata:sda    Disco SATA (default)
--nic   pcnet       NIC AMD PCnet (VMware viejo)
--nic   e1000       NIC Intel (default)
--mem   256         RAM en MB (default: 512)
--mac   00:0c:29:xx MAC original (ayuda DHCP)
--fix-grub          Arregla GRUB timeout=-1
--fix-modules       Arregla modules.conf + DHCP
--os    redhat      Fuerza fixes Red Hat/CentOS
--os    debian      Fuerza fixes Debian/Ubuntu
```

## Ejemplos

```bash
# Máquina moderna Ubuntu
./deploy.sh mivm ./images/mivm.qcow2

# Máquina vieja Red Hat 7.2
./deploy.sh kioptrix ./images/kioptrix.qcow2 --disk ide:hda --nic pcnet --mem 256 --fix-modules --os redhat

# Máquina con GRUB atascado
./deploy.sh tr0ll ./images/tr0ll.qcow2 --fix-grub --os debian
```

## Fixes que aplica

| Fix | Cuándo |
|-----|--------|
| Machine `pc` (i440FX) | Siempre |
| `<driver type='qcow2'/>` | Siempre (bug QEMU 11.x) |
| Firewall iptables | Siempre (UFW no bloquea DHCP) |
| GRUB timeout=3 | Con `--fix-grub` o auto-detect |
| modules.conf | Con `--fix-modules` o Red Hat |
| /etc/network/interfaces | Debian/Ubuntu |
| udev persistent rules | Debian/Ubuntu |

## Scripts

| Script | Función |
|--------|---------|
| `install.sh` | Instala todo lo necesario (1 vez) |
| `convert.sh` | .ova/.rar/.vmdk → .qcow2 |
| `deploy.sh` | Despliega cualquier VM con DHCP |
| `main.tf` | Alternativa con Terraform |
