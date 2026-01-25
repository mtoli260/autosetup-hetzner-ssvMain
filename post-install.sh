#!/bin/bash
set -euo pipefail

# -----------------------------
# Hetzner Post-Install Key-Only + User Hardening (ROBUST)
# -----------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- 0) Zielsystem Pfad ---
CHROOT="${FOLD:-/mnt}"

# --- Logging ---
LOGFILE="$CHROOT/root/post-install_log"
mkdir -p "$CHROOT/root"
touch "$LOGFILE"
chmod 600 "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "===== Post-Install gestartet: $(date) ====="
echo "CHROOT = $CHROOT"

# --- Basis-Mounts für sauberes chroot ---
echo "Mounting chroot base filesystems"
mount --bind /dev      "$CHROOT/dev"
mount --bind /dev/pts "$CHROOT/dev/pts"
mount -t proc proc    "$CHROOT/proc"
mount -t sysfs sys    "$CHROOT/sys"

# --- Sanity Check ---
if [ ! -x "$CHROOT/usr/sbin/useradd" ]; then
    echo "FEHLER: useradd nicht gefunden in $CHROOT/usr/sbin/useradd" >&2
    exit 1
fi

# --- 1) User "ssv" anlegen ---
if ! chroot "$CHROOT" /usr/bin/id ssv >/dev/null 2>&1; then
    echo "Erstelle User ssv"
    chroot "$CHROOT" /usr/sbin/useradd -m -s /bin/bash ssv
    chroot "$CHROOT" /usr/sbin/usermod -aG sudo ssv
else
    echo "User ssv existiert bereits"
fi

# --- 2) SSH Keys holen ---
SSH_KEYS_URL="https://github.com/mtoli260.keys"

echo "Erstelle .ssh Verzeichnisse"
mkdir -p "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"
chmod 700 "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"

echo "Lade SSH Keys von $SSH_KEYS_URL"

chroot "$CHROOT" /usr/bin/curl -fsSL "$SSH_KEYS_URL" -o /root/.ssh/authorized_keys
chroot "$CHROOT" /usr/bin/curl -fsSL "$SSH_KEYS_URL" -o /home/ssv/.ssh/authorized_keys

# Validierung: Datei darf nicht leer sein
if [ ! -s "$CHROOT/root/.ssh/authorized_keys" ]; then
    echo "FEHLER: root authorized_keys ist leer!" >&2
    exit 1
fi

if [ ! -s "$CHROOT/home/ssv/.ssh/authorized_keys" ]; then
    echo "FEHLER: ssv authorized_keys ist leer!" >&2
    exit 1
fi

echo "Setze Ownership und Rechte für authorized_keys"
chroot "$CHROOT" /bin/chown root:root /root/.ssh/authorized_keys
chroot "$CHROOT" /bin/chown ssv:ssv /home/ssv/.ssh/authorized_keys
chroot "$CHROOT" /bin/chmod 600 /root/.ssh/authorized_keys
chroot "$CHROOT" /bin/chmod 600 /home/ssv/.ssh/authorized_keys

# --- 3) Root + ssv Passwörter sperren ---
echo "Sperre Passwörter für root und ssv"
chroot "$CHROOT" /usr/bin/passwd -l root || true
chroot "$CHROOT" /usr/bin/passwd -l ssv  || true

# --- 4) SSH: Root-Login deaktivieren + Key-Only ---
echo "Konfiguriere SSH Key-Only Zugriff"
chroot "$CHROOT" /bin/mkdir -p /etc/ssh/sshd_config.d

cat >"$CHROOT/etc/ssh/sshd_config.d/99-keyonly.conf" <<'EOD'
# Enforce key-only SSH authentication
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOD

chroot "$CHROOT" /bin/chmod 644 /etc/ssh/sshd_config.d/99-keyonly.conf

# --- 5) SSH Syntax prüfen ---
echo "Prüfe sshd Konfiguration"
if chroot "$CHROOT" /usr/sbin/sshd -t; then
    echo "sshd_config Syntax OK"
else
    echo "WARNUNG: sshd_config Syntax-Fehler!" >&2
fi

echo "===== Post-Install abgeschlossen: $(date) ====="

# --- Reboot ---
echo "System wird neu gestartet..."
reboot
