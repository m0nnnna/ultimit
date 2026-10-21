#!/bin/sh
# Build the PinePhone Pro kernel as an Ubuntu .deb on an x86 PC (clang cross-builds, no gcc
# cross toolchain needed). Source: megi's tree; config: postmarketOS's linux-pine64-pinephonepro
# plus ubuntu.config. Usage: build.sh <workdir>
# Needs: clang lld llvm flex bison bc libelf-dev dwarves rsync cpio kmod dpkg-dev debhelper-compat
set -e
TAG=orange-pi-7.0-20260508-1436
PKGVER=7.0.5-ppp1
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1" && cd "$1"
[ -d linux ] || { curl -fL https://codeberg.org/megi/linux/archive/$TAG.tar.gz | tar xz; }
[ -f config-pmos ] || curl -fL -o config-pmos "https://gitlab.postmarketos.org/api/v4/projects/postmarketOS%2Fpmaports/repository/files/device%2Fcommunity%2Flinux-pine64-pinephonepro%2Fconfig-pine64-pinephonepro.aarch64/raw?ref=v26.06"
cd linux
cp ../config-pmos .config
scripts/kconfig/merge_config.sh -m .config "$here/ubuntu.config"
make ARCH=arm64 LLVM=1 olddefconfig
make -j"$(nproc)" ARCH=arm64 LLVM=1 Image.gz modules dtbs
# Packaging runs single-threaded: dtbs_install races on mkdir under -j.
# The headers package fails to cross-build its host tools, so only build the image.
make -j1 ARCH=arm64 LLVM=1 KDEB_PKGVERSION=$PKGVER DPKG_FLAGS=-d bindeb-pkg || true
ls -la ../linux-image-*_${PKGVER}_arm64.deb
