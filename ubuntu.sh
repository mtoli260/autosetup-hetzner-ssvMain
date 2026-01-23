#!/bin/bash
set -euo pipefail

### === KONFIGURATION === ###
HOSTNAME="ssvMain1"
ADMINUSER="admin"
GITHUB_USER="mtoli260"

IMAGE_FILE="Ubuntu-2404-noble-amd64-base.tar.gz"
SOURCE_IMAGE="/root/.oldroot/nfs/images/$IMAGE_FILE"
INSTALLIMAGE_CONF="/root/autosetup.conf"

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

echo "[+] Entferne alte Konfigurationsdateien"
rm -f "$INSTALLIMAGE_CONF" /post-install
sync

# --- Erstelle installimage Konfiguration ---
echo "[+] Erzeuge installimage-Konfiguration $INSTALLIMAGE_CONF"

cat > "$INSTALLIMAGE_CONF" <<EOF
## ======================================================
##  Hetzner Online GmbH - installimage - custom config
## ======================================================

## HARD DISK DRIVE(S):
DRIVE1=${DRIVES[0]}
DRIVE2=${DRIVES[1]}
DRIVE3=${DRIVES[2]}

## SOFTWARE RAID:
SWRAID 1
SWRAIDLEVEL 5

## HOSTNAME:
HOSTNAME=$HOSTNAME

## NETWORK CONFIG:
IPV4_ONLY no

## MISC CONFIG:
USE_KERNELMODE no

## PARTITIONS / FILESYSTEMS:
PART /boot ext4 1024M
PART /     ext4 all

## OPERATING SYSTEM IMAGE:
IMAGE=$SOURCE_IMAGE
EOF

# --- Erstelle post-install Skript ---
echo "[+] Erzeuge /post-install"
cat > /post-install <<'EOS'
#!/bin/bash
set -euxo pipefail

ADMINUSER="admin"
GITHUB_USER="mtoli260"

echo "[+] System Update"
apt update && apt -y upgrade

echo "[+] Admin-User anlegen"
useradd -m -s /bin/bash "$ADMINUSER" || true
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
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
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
cat >/etc/netplan/60-failover.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      addresses: []
NETPLAN
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

# Absoluter Pfad zu installimage im Hetzner Rescue-System
INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"

if [ -x "$INSTALLIMAGE_CMD" ]; then
  echo "[+] Gefundenes installimage: $INSTALLIMAGE_CMD — starte Installation"
  exec "$INSTALLIMAGE_CMD" -a -d -c "$INSTALLIMAGE_CONF"
else
  echo "[!] installimage wurde nicht gefunden unter $INSTALLIMAGE_CMD"
  echo "    Prüfe, ob das Rescue-System korrekt geladen wurde."
  exit 1
fi
