# PinePhone Pro (arm64) port

Dev branch only (`pinephone-pro`), not for main. Base: Ubuntu 26.04 (resolute) arm64,
stock `linux-image-generic`.

## Boot layout
- Tow-Boot (SPI) boots the **eMMC first**. Hold **Volume Down + power** to boot the SD card instead.
- SD card: stock postmarketOS, untouched. It is the rescue system.
- eMMC p1 `UBU_EFI` (FAT): standalone GRUB at `EFI/BOOT/BOOTAA64.EFI`, built from Ubuntu's
  `grub-efi-arm64-bin` with `grub-mkstandalone` (modules must include `gzio` and `loadenv`;
  pmOS's kernel is Image.gz) and `grub-embed.cfg` embedded. Menu: `grub/grub.cfg` (this dir).
  One-shot entry: `grub-editenv /boot/efi/grub/grubenv set next_entry=pmos`.
- eMMC p2 `ultimit-root` (ext4): Ubuntu.

## Building the rootfs (from pmOS on the SD card)
1. `apk add debootstrap tar zstd sgdisk dosfstools e2fsprogs`, plus Ubuntu's archive keyring
   in `/usr/share/keyrings/` (busybox tar can't unpack .debs).
2. Partition the eMMC as above, then `debootstrap --arch=arm64 --components=main,universe resolute ...`.
   Run it under `systemd-run`: it gets killed when the SSH session ends otherwise.
3. Copy `rootfs-setup.sh`, `zz-ppp-dtb`, an `authorized_keys`, the NM Wi-Fi profile and
   pmOS's `/lib/firmware/brcm/*pinephone-pro*` into the chroot's /tmp/fw, then run the script in the chroot.

## Hardware status (Ubuntu generic 7.0.0-38)
- Works: display console, eMMC, Wi-Fi (needs the RK818 32k clock modules in the initramfs and
  no `fw_devlink=off`), Panfrost GPU, RTC.
- Bluetooth: needs `brcm/BCM4345C0.hcd` (not in Ubuntu's linux-firmware).
- Missing: battery/charger (no RK818 charger driver in Ubuntu's kernel), USB-C on this unit
  (port fails to enumerate in every OS), modem, cameras (imx258 chip id read fails).
