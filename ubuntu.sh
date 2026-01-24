#!/bin/bash
set -euo pipefail

echo "[+] STOPPE evtl. vorhandene RAID-Arrays"
mdadm --stop /dev/md* 2>/dev/null || true

echo "[+] Prüfe Disk-Typ und lösche Signaturen"
if ls /dev/nvme*n1 >/dev/null 2>&1; then
  echo "→ NVMe erkannt"
  wipefs -fa /dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1
else
  echo "→ SATA erkannt"
  wipefs -fa /dev/sda /dev/sdb /dev/sdc
fi

echo "[+] Entferne alte Konfigurationsdateien"
/bin/rm -f /autosetup /post-install
sync


chmod +x /post-install


echo "[+] Starte installimage (ohne Parameter)"
INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"

if [ -x "$INSTALLIMAGE_CMD" ]; then
  exec "$INSTALLIMAGE_CMD"
else
  echo "[!] installimage wurde nicht gefunden unter $INSTALLIMAGE_CMD"
  exit 1
fi
