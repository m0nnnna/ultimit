#!/bin/sh
# Runs inside the Ubuntu chroot on the PinePhone Pro eMMC.
set -e
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
echo ultimit-ppp > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 ultimit-ppp\n' > /etc/hosts
cat > /etc/fstab <<F
LABEL=ultimit-root / ext4 defaults,noatime 0 1
LABEL=UBU_EFI /boot/efi vfat umask=0077 0 2
F
rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/ubuntu.sources <<S
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: resolute resolute-updates resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
S
apt-get update -q
apt-get install -yq --no-install-recommends linux-image-generic linux-firmware initramfs-tools \
  openssh-server network-manager wpasupplicant iw wireless-regdb sudo systemd-resolved \
  usbutils pciutils kmod less iproute2 iputils-ping curl
locale-gen en_US.UTF-8 >/dev/null
id mino >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,video,audio,input,render mino
echo mino:147147 | chpasswd
install -d -m700 -o mino -g mino /home/mino/.ssh
cp /tmp/authorized_keys /home/mino/.ssh/authorized_keys
chown mino:mino /home/mino/.ssh/authorized_keys; chmod 600 /home/mino/.ssh/authorized_keys
cp /tmp/Tripi.nmconnection /etc/NetworkManager/system-connections/
chmod 600 /etc/NetworkManager/system-connections/*
systemctl enable ssh NetworkManager systemd-resolved
# the chroot used the build host's resolv.conf; point it at resolved
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# Wi-Fi nvram for the PPP, in case Ubuntu's linux-firmware lacks it
for f in /tmp/fw/brcm/*pinephone-pro*; do
  b=$(basename "$f" .zst); [ -e /lib/firmware/brcm/$b ] || [ -e /lib/firmware/brcm/$b.zst ] || cp "$f" /lib/firmware/brcm/
done
cat >> /etc/initramfs-tools/modules <<M
# PinePhone Pro: RK818 PMIC, its 32k clock (Wi-Fi/BT need it), power sequencing
i2c_rk3x
rk8xx_i2c
clk_rk808
rk808_regulator
rtc_rk808
pwrseq_simple
M
install -m755 /tmp/zz-ppp-dtb /etc/kernel/postinst.d/zz-ppp-dtb
/etc/kernel/postinst.d/zz-ppp-dtb "$(ls /lib/modules | sort -V | tail -1)"
update-initramfs -u -k all
apt-get clean
ls /boot
