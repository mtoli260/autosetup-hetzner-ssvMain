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

echo "[+] Erzeuge /post-install"
cat > /post-install <<'EOS'
#!/bin/bash
set -euo pipefail
# -----------------------------
# Hetzner Post-Install Key-Only + User Hardening
# -----------------------------

# --- 0) Zielsystem Pfad ---
# installimage setzt $FOLD auf /root/.oldroot/hdd, aber wir gehen sicher:
CHROOT="${FOLD:-/mnt}"

# --- 1) User "ssv" anlegen ---
if ! chroot "$CHROOT" id ssv >/dev/null 2>&1; then
    chroot "$CHROOT" useradd -m -s /bin/bash ssv
    chroot "$CHROOT" usermod -aG sudo ssv
fi

# --- 2) SSH Keys holen ---
SSH_KEYS_URL="https://github.com/mtoli260.keys"

# Verzeichnisse anlegen
mkdir -p "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"
chmod 700 "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"

# Keys herunterladen (über Chroot, damit sie ins Zielsystem kommen)
chroot "$CHROOT" bash -c "curl -s $SSH_KEYS_URL -o /root/.ssh/authorized_keys"
chroot "$CHROOT" bash -c "curl -s $SSH_KEYS_URL -o /home/ssv/.ssh/authorized_keys"

# Rechte setzen
chroot "$CHROOT" chown root:root /root/.ssh/authorized_keys
chroot "$CHROOT" chown ssv:ssv /home/ssv/.ssh/authorized_keys
chroot "$CHROOT" chmod 600 /root/.ssh/authorized_keys
chroot "$CHROOT" chmod 600 /home/ssv/.ssh/authorized_keys

# --- 3) Root + ssv Passwörter sperren ---
chroot "$CHROOT" passwd -l root
chroot "$CHROOT" passwd -l ssv

# --- 4) SSH: Root-Login deaktivieren + Key-Only ---
chroot "$CHROOT" mkdir -p /etc/ssh/sshd_config.d
cat >"$CHROOT/etc/ssh/sshd_config.d/99-keyonly.conf" <<'EOD'
# Enforce key-only SSH authentication
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOD

chroot "$CHROOT" chmod 644 /etc/ssh/sshd_config.d/99-keyonly.conf

# --- 5) SSH Syntax prüfen ---
chroot "$CHROOT" sshd -t || echo "sshd_config Syntax Warning!"

echo "Post-Install Key-Only + User Hardening abgeschlossen"
EOS

chmod +x /post-install


echo "[+] Starte installimage (ohne Parameter)"
INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"

if [ -x "$INSTALLIMAGE_CMD" ]; then
  exec "$INSTALLIMAGE_CMD"
else
  echo "[!] installimage wurde nicht gefunden unter $INSTALLIMAGE_CMD"
  exit 1
fi
