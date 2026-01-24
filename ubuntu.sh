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

echo "[+] Erzeuge installimage-Konfiguration /autosetup"
cat > /autosetup <<'EOF'
## ======================================================
##  Hetzner Online GmbH - installimage - custom config
## ======================================================

## HARD DISK DRIVE(S):
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1
DRIVE3 /dev/nvme2n1

## SOFTWARE RAID:
SWRAID 1
SWRAIDLEVEL 5

## HOSTNAME:
HOSTNAME ssvMain1

## NETWORK CONFIG:
IPV4_ONLY no

## MISC CONFIG:
USE_KERNELMODE no

## PARTITIONS / FILESYSTEMS:
PART /boot ext4 1024M
PART / ext4 all

## OPERATING SYSTEM IMAGE:
IMAGE /root/.oldroot/nfs/install/../images/Ubuntu-2404-noble-amd64-base.tar.gz

# Lege User "ssv" an
USER_NAME ssv
USER_SHELL /bin/bash

# Beziehe SSH Public Keys von GitHub
SSHKEYS_URL https://github.com/mtoli260.keys

# Root-Login per SSH verbieten
PERMIT_ROOT_LOGIN no

# Erzwinge Key-Only Login (kein Passwort für root & ssv)
DISABLE_PASSWORD_AUTH yes
EOF

chmod +x /post-install


echo "[+] Starte installimage (ohne Parameter)"
INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"

if [ -x "$INSTALLIMAGE_CMD" ]; then
  exec "$INSTALLIMAGE_CMD"
else
  echo "[!] installimage wurde nicht gefunden unter $INSTALLIMAGE_CMD"
  exit 1
fi
