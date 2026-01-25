#!/bin/bash
set -euo pipefail

# -----------------------------
# Bootstrap Script für Hetzner Rescue
# Lädt autosetup + post-install, stoppt alte RAID-Arrays,
# löscht Signaturen, startet installimage automatisch
# -----------------------------

AUTOSETUP_URL="https://raw.githubusercontent.com/mtoli260/autosetup-hetzner-ssvMain/refs/heads/main/autosetup"
POSTINSTALL_URL="https://raw.githubusercontent.com/mtoli260/autosetup-hetzner-ssvMain/refs/heads/main/post-install.sh"

# Zielpfade im Rescue-System
AUTOSETUP_DEST="/root/autosetup"
POSTINSTALL_DEST="/root/post-install.sh"

# Alte RAIDs stoppen
echo "[+] STOPPE evtl. vorhandene RAID-Arrays"
mdadm --stop /dev/md* 2>/dev/null || true

# Festplatten wipe
echo "[+] Prüfe Disk-Typ und lösche Signaturen"
if ls /dev/nvme*n1 >/dev/null 2>&1; then
  echo "→ NVMe erkannt"
  wipefs -fa /dev/nvme0n1 /dev/nvme1n1
else
  echo "→ SATA erkannt"
  wipefs -fa /dev/sda /dev/sdb
fi

# Alte Dateien entfernen
echo "[+] Entferne alte Konfigurationsdateien"
rm -f "$AUTOSETUP_DEST" "$POSTINSTALL_DEST"
sync

echo "===== Bootstrap gestartet: $(date) ====="

# Lade autosetup
echo "[+] Lade autosetup..."
curl -fsSL "$AUTOSETUP_URL" -o "$AUTOSETUP_DEST"

# Lade post-install.sh
echo "[+] Lade post-install.sh..."
curl -fsSL "$POSTINSTALL_URL" -o "$POSTINSTALL_DEST"

# Validierung
for f in "$AUTOSETUP_DEST" "$POSTINSTALL_DEST"; do
  if [ ! -s "$f" ]; then
    echo "FEHLER: $f ist leer oder fehlt!" >&2
    exit 1
  fi
done

# Rechte setzen
chmod 600 "$AUTOSETUP_DEST"
chmod +x "$POSTINSTALL_DEST"

echo "[+] Dateien erfolgreich abgelegt:"
ls -l "$AUTOSETUP_DEST" "$POSTINSTALL_DEST"

echo "Kurzer Inhalt-Check:"
head -n 5 "$AUTOSETUP_DEST"
head -n 5 "$POSTINSTALL_DEST"

echo "===== Bootstrap abgeschlossen ====="

# Installimage starten mit Post-Install-Script
echo "[+] Starte installimage mit /root/autosetup + Post-Install"
bash /root/.oldroot/nfs/install/installimage -a -c "$AUTOSETUP_DEST" -x "$POSTINSTALL_DEST"
