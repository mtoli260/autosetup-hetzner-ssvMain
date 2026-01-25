#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# -----------------------------
# Config
# -----------------------------
USERNAME="ssv"
SSH_KEYS_URL="https://github.com/mtoli260.keys"
TIMEZONE="Europe/Berlin"

echo "===== DebPostInstall (automated) gestartet: $(date) ====="

# -----------------------------
# System Update
# -----------------------------
echo "Updating the system..."
apt update
apt full-upgrade -y
apt autoremove -y
apt autoclean -y

# -----------------------------
# Install necessary packages
# -----------------------------
echo "Installing necessary packages..."
apt-get install -y sudo openssh-server ufw systemd-timesyncd vim htop net-tools curl wget git

# -----------------------------
# User ssv anlegen (falls nicht vorhanden)
# -----------------------------
if ! id "$USERNAME" &>/dev/null; then
    echo "Creating user $USERNAME"
    useradd -m -s /bin/bash -G sudo "$USERNAME"
else
    echo "User $USERNAME already exists"
fi

# -----------------------------
# SSH Keys für root + ssv
# -----------------------------
echo "Configuring SSH keys from GitHub for root and $USERNAME"

for U in root "$USERNAME"; do
    HOME_DIR=$(eval echo "~$U")
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"

    curl -fsSL "$SSH_KEYS_URL" -o "$HOME_DIR/.ssh/authorized_keys"

    if [ ! -s "$HOME_DIR/.ssh/authorized_keys" ]; then
        echo "ERROR: authorized_keys for $U is empty!" >&2
        exit 1
    fi

    chmod 600 "$HOME_DIR/.ssh/authorized_keys"
    chown -R "$U:$U" "$HOME_DIR/.ssh"
done

# -----------------------------
# Lock passwords (key-only)
# -----------------------------
echo "Locking passwords for root and $USERNAME"
passwd -l root || true
passwd -l "$USERNAME" || true

# -----------------------------
# SSH Hardening (key-only, no root)
# -----------------------------
echo "Hardening SSH configuration"

mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/99-keyonly.conf <<'EOD'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOD

chmod 644 /etc/ssh/sshd_config.d/99-keyonly.conf

# Validate SSH config
sshd -t

systemctl restart ssh

# -----------------------------
# UFW Firewall
# -----------------------------
echo "Configuring UFW firewall"
ufw allow OpenSSH
ufw --force enable

# -----------------------------
# Timezone + Time Sync
# -----------------------------
echo "Setting timezone to $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "Enabling systemd-timesyncd"
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd

# -----------------------------
# NO SWAP (explicitly ensure none is configured)
# -----------------------------
echo "Ensuring no swap is configured"
swapoff -a || true
sed -i '/swapfile/d' /etc/fstab

echo "===== DebPostInstall (automated) abgeschlossen: $(date) ====="

# --- Reboot ---
echo "System wird neu gestartet..."
reboot
