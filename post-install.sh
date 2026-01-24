!/bin/bash
set -euo pipefail

# -----------------------------
# Hetzner Post-Install Key-Only + User Hardening
# -----------------------------

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

# --- 1) User "ssv" anlegen ---
if ! chroot "$CHROOT" id ssv >/dev/null 2>&1; then
    echo "Erstelle User ssv"
    chroot "$CHROOT" useradd -m -s /bin/bash ssv
    chroot "$CHROOT" usermod -aG sudo ssv
else
    echo "User ssv existiert bereits"
fi

# --- 2) SSH Keys holen ---
SSH_KEYS_URL="https://github.com/mtoli260.keys"

echo "Erstelle .ssh Verzeichnisse"
mkdir -p "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"
chmod 700 "$CHROOT/root/.ssh" "$CHROOT/home/ssv/.ssh"

echo "Lade SSH Keys von $SSH_KEYS_URL"

chroot "$CHROOT" bash -c "curl -fsSL $SSH_KEYS_URL -o /root/.ssh/authorized_keys"
chroot "$CHROOT" bash -c "curl -fsSL $SSH_KEYS_URL -o /home/ssv/.ssh/authorized_keys"

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
chroot "$CHROOT" chown root:root /root/.ssh/authorized_keys
chroot "$CHROOT" chown ssv:ssv /home/ssv/.ssh/authorized_keys
chroot "$CHROOT" chmod 600 /root/.ssh/authorized_keys
chroot "$CHROOT" chmod 600 /home/ssv/.ssh/authorized_keys

# --- 3) Root + ssv Passwörter sperren ---
echo "Sperre Passwörter für root und ssv"
chroot "$CHROOT" passwd -l root || true
chroot "$CHROOT" passwd -l ssv || true

# --- 4) SSH: Root-Login deaktivieren + Key-Only ---
echo "Konfiguriere SSH Key-Only Zugriff"
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
echo "Prüfe sshd Konfiguration"
if chroot "$CHROOT" sshd -t; then
    echo "sshd_config Syntax OK"
else
    echo "WARNUNG: sshd_config Syntax-Fehler!" >&2
fi

echo "===== Post-Install abgeschlossen: $(date) ====="

# --- Reboot (optional, bewusst aktiv lassen oder auskommentieren) ---
echo "System wird neu gestartet..."
reboot
