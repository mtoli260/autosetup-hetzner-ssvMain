#!/bin/bash
set -e

### === KONFIGURATION === ###
HOSTNAME="ssvMain1"
ADMINUSER="admin"
GITHUB_USER="mtoli260"

IMAGE="Ubuntu-2404-noble-amd64-base.tar.gz"
INSTALLIMAGE="/autosetup"

DRIVES=(
  /dev/nvme0n1
  /dev/nvme1n1
  /dev/nvme2n1
)
### ====================== ###

echo "[+] STOPPE evtl. vorhandene RAID-Arrays"
mdadm --stop /dev/md* 2>/dev/null || true

echo "[+] Prüfe Disk-Typ und lösche Signaturen"
if ls /dev/nvme*n1 >/dev/null 2>&1; then
  echo "→ NVMe erkannt"
  wipefs -fa /dev/nvme*n1
else
  echo "→ SATA erkannt"
  wipefs -fa /dev/sd*
fi

# --- Neu: Vor dem Erzeugen prüfen und alte /autosetup und /post-install entfernen ---
echo "[+] Entferne vorhandene /autosetup und /post-install (falls vorhanden)"
if [ -e "$INSTALLIMAGE" ]; then
  echo "  → Entferne $INSTALLIMAGE"
  rm -f "$INSTALLIMAGE"
fi

if [ -e "/post-install" ]; then
  echo "  → Entferne /post-install"
  rm -f "/post-install"
fi
sync

echo "[+] Erzeuge installimage-Konfiguration"

cat > "$INSTALLIMAGE" <<EOF
IMAGE=/root/.oldroot/nfs/install/../Images/$IMAGE

HOSTNAME=$HOSTNAME

DRIVE1=${DRIVES[0]}
DRIVE2=${DRIVES[1]}
DRIVE3=${DRIVES[2]}

USE_KERNEL_MODE_SETTING yes

SWRAID=1
SWRAIDLEVEL=5

PART /boot ext3 1024M
PART / ext4 all

POSTINSTALL=1
EOF

echo "[+] Erzeuge /post-install (Postinstall-Skript für das Zielsystem)"

cat > /post-install <<'EOS'
#!/bin/bash
set -e

ADMINUSER="admin"
GITHUB_USER="mtoli260"

echo "[+] System Update"
apt update && apt -y upgrade

echo "[+] Admin-User anlegen"
useradd -m -s /bin/bash "$ADMINUSER"
usermod -aG sudo "$ADMINUSER"

mkdir -p /home/$ADMINUSER/.ssh
curl -fsSL https://github.com/$GITHUB_USER.keys > /home/$ADMINUSER/.ssh/authorized_keys
chmod 700 /home/$ADMINUSER/.ssh
chmod 600 /home/$ADMINUSER/.ssh/authorized_keys
chown -R $ADMINUSER:$ADMINUSER /home/$ADMINUSER/.ssh

echo "[+] SSH Hardening"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl reload ssh || true

echo "[+] Docker installieren"
apt -y install ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
> /etc/apt/sources.list.d/docker.list

apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$ADMINUSER"

echo "[+] Firewall (UFW)"
apt -y install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 13001/tcp
ufw allow 12001/udp
ufw --force enable

echo "[+] Failover-IP Vorbereitung (Netplan)"
cat >/etc/netplan/60-failover.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      addresses: []
EOF

netplan apply || true

echo "[+] RAID Monitoring"
apt -y install mdadm
sed -i 's/^#MAILADDR.*/MAILADDR root/' /etc/mdadm/mdadm.conf
update-initramfs -u

echo "[+] eth-docker ins Admin-Home klonen"
sudo -u $ADMINUSER bash <<'GITCLONE'
cd /home/$ADMINUSER
git clone https://github.com/ethstaker/eth-docker.git ssv-node
cd ssv-node
GITCLONE

echo "[+] Postinstall abgeschlossen"
EOS

chmod +x /post-install

echo "[+] Starte automatische Installation"

# Robustes Auffinden und Ausführen von installimage
INSTALLIMAGE_CMD="$(command -v installimage 2>/dev/null || true)"

# Wenn nicht im PATH, prüfe den Alias-Zielpfad, den du interaktiv hattest
if [ -z "$INSTALLIMAGE_CMD" ] && [ -x "/root/.oldroot/nfs/install/installimage" ]; then
  INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"
fi

# Falls noch immer nicht gefunden, erweitere PATH um übliche Systempfade und suche erneut
if [ -z "$INSTALLIMAGE_CMD" ]; then
  export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
  INSTALLIMAGE_CMD="$(command -v installimage 2>/dev/null || true)"
fi

if [ -n "$INSTALLIMAGE_CMD" ]; then
  echo "[+] Gefundenes installimage: $INSTALLIMAGE_CMD — starte Installation"
  exec "$INSTALLIMAGE_CMD"
else
  echo "[!] installimage wurde nicht gefunden. Bitte prüfe interaktiv:"
  echo "    type installimage   # zeigt alias und Ziel"
  echo "    ls -l /root/.oldroot/nfs/install/installimage"
  echo "Oder setze PATH manuell: export PATH=/sbin:/usr/sbin:/bin:/usr/bin:\$PATH"
  exit 1
fi
