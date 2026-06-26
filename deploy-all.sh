#!/bin/bash
# ============================================================
# Deploy ALL VMs from ./images/
# ============================================================
set -e
echo "[*] Desplegando todas las VMs..."

[ -f ./images/kioptrix.qcow2 ] && ./deploy-kioptrix.sh ./images/kioptrix.qcow2
[ -f ./images/tr0ll.qcow2 ]    && ./deploy-tr0ll.sh ./images/tr0ll.qcow2
[ -f ./images/mrrobot.qcow2 ]  && ./deploy-mrrobot.sh ./images/mrrobot.qcow2

echo ""
echo "[*] Todas las VMs desplegadas"
virsh net-dhcp-leases vulnhub_lab 2>/dev/null
