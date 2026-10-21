# PinePhone Pro (arm64) port

Dev branch only (`pinephone-pro`), not for main. Base: Ubuntu 26.04 (resolute) arm64.
Kernel: `linux-image-7.0.5-ppp` (megi's PinePhone Pro tree, built by `kernel/build.sh`),
with Ubuntu's `linux-image-generic` kept as the GRUB fallback.

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

## Kernel
`kernel/build.sh <workdir>` builds the .deb on the x86 desktop (~15 min). Install it on the phone with
`dpkg -i`; the `zz-ppp-dtb` hooks (install to /etc/kernel/postinst.d and postrm.d) put each kernel's
device tree at /boot/dtb-<version>, which `grub.cfg` loads. Kernel versions are set at the top of `grub.cfg`.

## Hardware status, ppp kernel 7.0.5
- Works: display console, eMMC, Wi-Fi, Bluetooth (`brcm/BCM4345C0.hcd`, copied from pmOS), battery and
  charger (rk818), Panfrost GPU, RTC.
- Not checked yet: modem, cameras, audio, suspend.
- USB-C on this unit fails to enumerate in every OS (hardware).

## Hardware status, Ubuntu generic 7.0.0-38 (fallback)
- Works: display console, eMMC, Wi-Fi (needs the RK818 32k clock modules in the initramfs and
  no `fw_devlink=off`), Panfrost GPU, RTC.
- Bluetooth: needs `brcm/BCM4345C0.hcd` (not in Ubuntu's linux-firmware).
- Missing: battery/charger (no RK818 charger driver in Ubuntu's kernel), USB-C on this unit
  (port fails to enumerate in every OS), modem, cameras (imx258 chip id read fails).
