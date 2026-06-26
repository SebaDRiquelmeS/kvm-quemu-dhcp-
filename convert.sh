#!/bin/bash
# Convierte imagenes VulnHub (.rar/.ova/.vmdk) a .qcow2
# Uso: ./convert.sh <archivo.rar|archivo.ova|archivo.vmdk> [nombre_salida]

set -e
SRC="$1"
OUT_DIR="./images"

mkdir -p "$OUT_DIR"

if [ ! -f "$SRC" ]; then
    echo "Uso: $0 <archivo.rar|.ova|.vmdk>"
    exit 1
fi

BASENAME=$(basename "$SRC")
EXT="${BASENAME##*.}"
NAME="${2:-${BASENAME%.*}}"

echo "[*] Procesando: $SRC"

case "$EXT" in
    rar|RAR)
        echo "  Extrayendo .rar..."
        TMPDIR=$(mktemp -d)
        bsdtar -xf "$SRC" -C "$TMPDIR"
        VMDK=$(find "$TMPDIR" -name "*.vmdk" | head -1)
        if [ -n "$VMDK" ]; then
            echo "  Convirtiendo $VMDK..."
            qemu-img convert -f vmdk -O qcow2 "$VMDK" "$OUT_DIR/${NAME}.qcow2"
        fi
        rm -rf "$TMPDIR"
        ;;
    ova|OVA)
        echo "  Extrayendo .ova..."
        TMPDIR=$(mktemp -d)
        bsdtar -xf "$SRC" -C "$TMPDIR"
        VMDK=$(find "$TMPDIR" -name "*.vmdk" | head -1)
        if [ -n "$VMDK" ]; then
            echo "  Convirtiendo $VMDK..."
            qemu-img convert -f vmdk -O qcow2 "$VMDK" "$OUT_DIR/${NAME}.qcow2"
        fi
        rm -rf "$TMPDIR"
        ;;
    vmdk|VMDK)
        echo "  Convirtiendo directamente..."
        qemu-img convert -f vmdk -O qcow2 "$SRC" "$OUT_DIR/${NAME}.qcow2"
        ;;
    *)
        echo "Formato no soportado: .$EXT"
        exit 1
        ;;
esac

echo "[OK] $OUT_DIR/${NAME}.qcow2"
ls -lh "$OUT_DIR/${NAME}.qcow2"
