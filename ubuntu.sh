#!/bin/bash
set -euo pipefail

AUTOSETUP_URL="https://raw.githubusercontent.com/mtoli260/autosetup-hetzner-ssvMain/refs/heads/main/autosetup"
POSTINSTALL_URL="https://raw.githubusercontent.com/mtoli260/autosetup-hetzner-ssvMain/refs/heads/main/post-install.sh"

AUTOSETUP_DEST="/autosetup"
POSTINSTALL_DEST="/temp/post-install.sh"

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

echo "===== Bootstrap gestartet: $(date) ====="

echo "Lade autosetup..."
curl -fsSL "$AUTOSETUP_URL" -o "$AUTOSETUP_DEST"

echo "Lade post-install.sh..."
curl -fsSL "$POSTINSTALL_URL" -o "$POSTINSTALL_DEST"

# Validierung
for f in "$AUTOSETUP_DEST" "$POSTINSTALL_DEST"; do
  if [ ! -s "$f" ]; then
    echo "FEHLER: $f ist leer oder fehlt!" >&2
    exit 1
  fi
done

# Rechte
chmod 600 "$AUTOSETUP_DEST"
chmod +x "$POSTINSTALL_DEST"

echo "Dateien erfolgreich abgelegt:"
ls -l /autosetup /temp/post-install.sh

echo "Kurzer Inhalt-Check:"
head -n 5 /autosetup
head -n 5 /temp/post-install.sh

echo "===== Bootstrap abgeschlossen ====="

# OPTIONAL: installimage direkt starten
echo "Starte installimage mit /autosetup"
bash /root/.oldroot/nfs/install/installimage -a -c /autoinstall -x /tmp/post-install.sh 

