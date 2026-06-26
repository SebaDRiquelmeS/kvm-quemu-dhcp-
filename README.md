# KVM + QEMU → Laboratorio de Pentesting con DHCP

Scripts para desplegar **cualquier** máquina VulnHub con DHCP funcional desde cero.

## Un comando

```bash
./convert.sh ~/Downloads/Maquina.rar maquina
./deploy.sh maquina ./images/maquina.qcow2
```

## Scripts

| Script | Qué hace |
|--------|----------|
| `deploy.sh` | **Genérico** — despliega cualquier VM VulnHub |
| `deploy-kioptrix.sh` | Kioptrix Level 1 (Baja) preconfigurado |
| `deploy-tr0ll.sh` | Tr0ll (Media) preconfigurado |
| `deploy-mrrobot.sh` | Mr. Robot (Alta) preconfigurado |
| `deploy-all.sh` | Despliega las 3 si están en `./images/` |
| `convert.sh` | Convierte `.rar`/`.ova`/`.vmdk` a `.qcow2` |

## Uso

```bash
# 1. Clonar
git clone git@github.com:SebaDRiquelmeS/kvm-quemu-dhcp-.git
cd kvm-quemu-dhcp-

# 2. Convertir
./convert.sh ~/Downloads/Kioptrix_Level_1.rar kioptrix
./convert.sh ~/Downloads/Tr0ll.rar tr0ll
./convert.sh ~/Downloads/mrRobot.ova mrrobot

# 3. Desplegar
./deploy-all.sh
```

## Para tu propia máquina VulnHub

```bash
./convert.sh ~/Downloads/MiMaquina.ova mimaquina
./deploy.sh mimaquina ./images/mimaquina.qcow2
```

Opciones disponibles en `deploy.sh`:

```
--disk  ide:hda       # Disco IDE (maquinas viejas)
--disk  sata:sda      # Disco SATA (default)
--nic   pcnet         # NIC AMD PCnet (VMs VMware viejas)
--nic   e1000         # NIC Intel e1000 (default)
--mem   256           # RAM en MB
--mac   00:0c:29:...  # MAC original (ayuda con DHCP)
--fix-grub            # Corrige timeout=-1 de GRUB
--fix-modules         # Corrige alias eth0 en modules.conf
--os    redhat        # Tipo de SO
--os    debian
```

## Fixes que aplica automáticamente

| Fix | Cuándo |
|-----|--------|
| `machine='pc'` | Siempre (NIC visible en bus PCI) |
| `<driver type='qcow2'/>` | Siempre (bug QEMU 11.x -blockdev) |
| Firewall iptables | Siempre (UFW bloquea DHCP) |
| GRUB timeout=3 | Si detecta `timeout=-1` |
| modules.conf alias | Con `--fix-modules` o auto-detect Red Hat |
| DHCP_HOSTNAME | Con `--fix-modules` o auto-detect Red Hat |
| /etc/network/interfaces | Auto-detect Debian/Ubuntu |
| udev persistent rules | Auto-detect Debian/Ubuntu |

## Requisitos

```bash
sudo pacman -S libvirt qemu-base qemu-nbd
sudo usermod -aG libvirt $USER
# Re-login
```
