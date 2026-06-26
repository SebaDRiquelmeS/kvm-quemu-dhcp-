#!/bin/bash
# ============================================================
# Instalar dependencias para KVM + QEMU + DHCP VulnHub Lab
# Ejecutar una sola vez en sistema limpio
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
skip(){ echo -e "${YELLOW}[SKIP]${NC} $1"; }
err() { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

echo "========================================"
echo "  Instalando dependencias KVM+QEMU"
echo "========================================"

# ── Sistema de paquetes ──
if command -v pacman &>/dev/null; then
    PKG_MGR="pacman -S --noconfirm"
    PKG_LIST="libvirt qemu-base qemu-nbd terraform"
elif command -v apt &>/dev/null; then
    PKG_MGR="apt install -y"
    PKG_LIST="libvirt-daemon-system qemu-kvm qemu-utils qemu-block-extra terraform"
else
    err "Solo soporta Arch (pacman) y Debian/Ubuntu (apt)"
fi

# ── Instalar paquetes ──
echo "[*] Detectando paquetes faltantes..."
MISSING=""
for pkg in $PKG_LIST; do
    if command -v "$pkg" &>/dev/null || dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || pacman -Q "$pkg" &>/dev/null; then
        skip "$pkg ya instalado"
    else
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "[*] Instalando:$MISSING"
    sudo $PKG_MGR $MISSING
else
    ok "Todos los paquetes instalados"
fi

# ── Grupo libvirt ──
if groups "$USER" | grep -q libvirt; then
    skip "Usuario $USER ya en grupo libvirt"
else
    echo "[*] Agregando $USER al grupo libvirt..."
    sudo usermod -aG libvirt "$USER"
    ok "Agregado. Cierra sesion y vuelve a entrar para que tome efecto"
fi

# ── Servicio libvirtd ──
if systemctl is-active --quiet libvirtd; then
    skip "libvirtd ya corriendo"
else
    echo "[*] Iniciando libvirtd..."
    sudo systemctl enable --now libvirtd
    ok "libvirtd iniciado"
fi

# ── nbd kernel module ──
if lsmod | grep -q nbd; then
    skip "nbd module ya cargado"
else
    echo "[*] Cargando modulo nbd..."
    sudo modprobe nbd max_part=8 2>/dev/null || true
    ok "nbd cargado"
fi

# ── Pool de storage default ──
if virsh pool-info default &>/dev/null; then
    skip "Storage pool default ya existe"
else
    echo "[*] Creando storage pool default..."
    virsh pool-define-as default dir - - - - /var/lib/libvirt/images
    virsh pool-start default 2>/dev/null || true
    virsh pool-autostart default 2>/dev/null || true
fi

# ── Red default (limpiar si existe) ──
if virsh net-info default &>/dev/null; then
    ok "Red default existe"
else
    virsh net-start default 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}========================================"
echo "  Instalacion completa"
echo "========================================"
echo ""
echo "  Si era primera vez, cerra sesion y volve a entrar"
echo "  Luego: ./deploy.sh <nombre> ./images/<maquina>.qcow2"
