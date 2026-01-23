#!/bin/bash
set -e

### === KONFIGURATION === ###
HOSTNAME="ssvMain1"
ADMINUSER="ssv"
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

echo "[+] Entferne vorhandene /autosetup und /post-install (falls vorhanden)"
rm -f "$INSTALLIMAGE" /post-install 2>/dev/null || true
sync

echo "[+] Erzeuge installimage-Konfiguration"

cat > "$INSTALLIMAGE" <<EOF
## ======================================================
##  Hetzner Online GmbH - installimage - custom config
## ======================================================

DRIVE1=${DRIVES[0]}
DRIVE2=${DRIVES[1]}
DRIVE3=${DRIVES[2]}

SWRAID 1
SWRAIDLEVEL 5

HOSTNAME=$HOSTNAME

IPV4_ONLY no
USE_KERNELMODE no

PART /boot ext4 1024M
PART /     ext4 all

IMAGE=/root/.oldroot/nfs/install/../images/$IMAGE
EOF

echo "[+] Erzeuge /post-install"

cat > /post-install <<'EOS'
#!/bin/bash
set -e

ADMINUSER="ssv"
GITHUB_USER="mtoli260"

export DEBIAN_FRONTEND=noninteractive

echo "[+] System Update"
apt-get update
apt-get -y upgrade

echo "[+] Basis-Pakete"
apt-get install -y ca-certificates curl gnupg lsb-release

echo "[+] User anlegen"
if ! id "$ADMINUSER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$ADMINUSER"
fi
usermod -aG sudo "$ADMINUSER"

echo "[+] SSH Keys von GitHub laden"
mkdir -p /home/$ADMINUSER/.ssh
chmod 700 /home/$ADMINUSER/.ssh

curl -fsSL https://github.com/$GITHUB_USER.keys > /home/$ADMINUSER/.ssh/authorized_keys

chmod 600 /home/$ADMINUSER/.ssh/authorized_keys
chown -R $ADMINUSER:$ADMINUSER /home/$ADMINUSER/.ssh

echo "[+] SSH Hardening"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

echo "[+] Chrony (Zeit-Sync)"
apt-get install -y chrony
systemctl enable chrony
systemctl restart chrony

echo "[+] Unattended Upgrades"
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "[+] Docker (APT Repo + Keyring)"
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo \$VERSION_CODENAME) stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

usermod -aG docker "$ADMINUSER"

echo "[+] Firewall (UFW)"
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
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

echo "[+] noatime aktivieren"
sed -i 's/ defaults / defaults,noatime /' /etc/fstab || true
mount -o remount / || true

echo "[+] Swappiness"
grep -q vm.swappiness /etc/sysctl.conf || echo "vm.swappiness=1" >> /etc/sysctl.conf
sysctl -p

echo "[+] RAID + SMART Monitoring"
apt-get install -y mdadm smartmontools
mdadm --detail --scan >> /etc/mdadm/mdadm.conf || true
update-initramfs -u || true

echo "[+] eth-docker klonen"
su - "$ADMINUSER" -c "
cd /home/$ADMINUSER
git clone https://github.com/ethstaker/eth-docker.git ssv-node
cd ssv-node
"

echo "[+] Postinstall abgeschlossen"
EOS

chmod +x /post-install

echo "[+] Starte automatische Installation"

INSTALLIMAGE_CMD="$(command -v installimage 2>/dev/null || true)"

if [ -z "$INSTALLIMAGE_CMD" ] && [ -x "/root/.oldroot/nfs/install/installimage" ]; then
  INSTALLIMAGE_CMD="/root/.oldroot/nfs/install/installimage"
fi

if [ -z "$INSTALLIMAGE_CMD" ]; then
  export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
  INSTALLIMAGE_CMD="$(command -v installimage 2>/dev/null || true)"
fi

if [ -n "$INSTALLIMAGE_CMD" ]; then
  echo "[+] Gefundenes installimage: $INSTALLIMAGE_CMD — starte Installation"
  exec "$INSTALLIMAGE_CMD" -a -d -c /autosetup
else
  echo "[!] installimage wurde nicht gefunden."
  exit 1
fi
