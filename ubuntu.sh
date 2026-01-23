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
PART /boot ext3 1024M
PART / ext4 all

## OPERATING SYSTEM IMAGE:
IMAGE /root/.oldroot/nfs/install/../images/Ubuntu-2404-noble-amd64-base.tar.gz
EOF

echo "[+] Erzeuge /post-install"
cat > /post-install <<'EOS'
#!/bin/bash
set -euxo pipefail

echo "[+] System Update"
apt update && apt -y upgrade

echo "[+] Admin-User anlegen"
useradd -m -s /bin/bash admin || true
usermod -aG sudo admin

mkdir -p /home/admin/.ssh
curl -fsSL https://github.com/mtoli260.keys > /home/admin/.ssh/authorized_keys
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys
chown -R admin:admin /home/admin/.ssh

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
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker admin

echo "[+] Firewall (UFW)"
apt -y install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 13001/tcp
ufw allow 12001/udp
ufw --force enable

echo "[+] RAID Monitoring"
apt -y install mdadm
sed -i 's/^#MAILADDR.*/MAILADDR root/' /etc/mdadm/mdadm.conf
update-initramfs -u

echo "[+] eth-docker ins Admin-Home klonen"
sudo -u admin bash <<'GITCLONE'
cd /home/admin
git clone https://github.com/ethstaker/eth-docker.git ssv-node
cd ssv-node
GITCLONE

echo "[+] Postinstall abgeschlossen"
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
