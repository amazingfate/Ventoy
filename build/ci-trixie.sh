#!/bin/sh
# Build GRUB, EDK2, and the loongarch64 tools in Debian trixie.
# GRUB and EDK2 are one source tree for every architecture. CentOS 7 has
# no loongarch64 compiler, so the LoongArch initramfs tools and EfiFs
# drivers are built here too. The other installers and the release
# package are build/ci-centos.sh, which reads build/out from this script.
#
#   docker compose run -T --rm --build trixie

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ "$(id -u)" -ne 0 ]; then
    echo "build/ci-trixie.sh needs root. Run it in privileged docker." >&2
    exit 1
fi

# hexdump counts the shim hash placeholder in build-edk2.sh. On trixie it
# comes from bsdextrautils, which the old single-container script installed.
if ! command -v git >/dev/null 2>&1 || ! command -v patch >/dev/null 2>&1 || ! command -v hexdump >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends git patch bsdextrautils
fi

echo "=== GRUB ==="
sh "$ROOT/build/build-grub.sh" \
    x86_64-efi i386-efi arm64-efi loongarch64-efi mips64el-efi i386-pc
test -f "$ROOT/build/out/images/core.img"
test -f "$ROOT/build/out/images/grubx64_real.efi"
test -f "$ROOT/INSTALL/EFI/BOOT/BOOTX64.EFI"
test -f "$ROOT/INSTALL/EFI/BOOT/mmx64.efi"
if ! grep -a -q 'sbat,' "$ROOT/INSTALL/EFI/BOOT/BOOTX64.EFI"; then
    echo "BOOTX64.EFI is not the signed shim" >&2
    exit 1
fi
if grep -a -q 'GNU GRUB' "$ROOT/INSTALL/EFI/BOOT/BOOTX64.EFI"; then
    echo "BOOTX64.EFI must stay the Rocky shim" >&2
    exit 1
fi
test -f "$ROOT/INSTALL/EFI/BOOT/BOOTIA32.EFI"
test -f "$ROOT/INSTALL/EFI/BOOT/grubia32.efi"
test -f "$ROOT/INSTALL/EFI/BOOT/mmia32.efi"
if ! grep -a -q 'sbat,' "$ROOT/INSTALL/EFI/BOOT/BOOTIA32.EFI"; then
    echo "BOOTIA32.EFI is not the signed shim" >&2
    exit 1
fi
if grep -a -q 'GNU GRUB' "$ROOT/INSTALL/EFI/BOOT/BOOTIA32.EFI"; then
    echo "BOOTIA32.EFI must stay the Super-UEFIinSecureBoot-Disk shim" >&2
    exit 1
fi
test -f "$ROOT/build/out/images/grubia32_real.efi"
test -f "$ROOT/build/out/images/BOOTAA64.EFI"
test -f "$ROOT/build/out/images/BOOTLOONGARCH64.EFI"
test -f "$ROOT/build/out/images/BOOTMIPS.EFI"
test -f "$ROOT/build/out/prefix-i386-pc/sbin/grub-bios-setup"
test -f "$ROOT/INSTALL/EFI/BOOT/grubx64_real.efi"
test -f "$ROOT/INSTALL/EFI/BOOT/grubia32_real.efi"
test -f "$ROOT/LiveCDGUI/GRUB/bootx64.efi"
test -f "$ROOT/LiveCDGUI/GRUB/cdrom.img"

echo "=== EDK2 ==="
sh "$ROOT/build/build-edk2.sh" X64 IA32 AARCH64 LOONGARCH64
test -f "$ROOT/INSTALL/EFI/BOOT/fbx64.efi"
test -f "$ROOT/INSTALL/EFI/BOOT/fbia32.efi"
test -f "$ROOT/INSTALL/EFI/BOOT/fbaa64.efi"
test -f "$ROOT/build/out/edk2/X64/Ventoy.efi"
test -f "$ROOT/build/out/edk2/IA32/Ventoy.efi"
test -f "$ROOT/build/out/edk2/AARCH64/Ventoy.efi"
test -f "$ROOT/build/out/edk2/LOONGARCH64/Ventoy.efi"

echo "=== EfiFs drivers ==="
# x86 and arm64 keep the iso9660/udf drivers already in INSTALL/ventoy.
# Only LoongArch has no upstream driver.
sh "$ROOT/build/build-efifs.sh" LOONGARCH64
test -f "$ROOT/build/out/efifs/iso9660_loongarch64.efi"
test -f "$ROOT/build/out/efifs/udf_loongarch64.efi"

echo "=== loongarch64 initramfs tools ==="
# x86, arm64 and mips64 keep the binaries already in IMG/cpio_*.
# A previous local build may have left glibc tools in build/out; those
# would override the upstream blobs inside mkcpio.sh, so drop them.
# Only LoongArch has no upstream initramfs.
for arch in x86_64 i386 aarch64 mips64el; do
    rm -rf "$ROOT/build/out/tools/$arch" "$ROOT/build/out/initramfs/$arch"
done
if [ ! -x "$ROOT/build/out/tools/loongarch64/vtoytool" ] || \
   [ ! -f "$ROOT/build/out/initramfs/loongarch64/busybox.xz" ]; then
    sh "$ROOT/build/build-user.sh" loongarch64
    sh "$ROOT/build/build-init-busybox.sh" loongarch64
fi
for bin in dmsetup unsquashfs vtoy_fuse_iso vtoytool vblade lunzip lz4cat zstdcat xzminidec; do
    test -f "$ROOT/build/out/tools/loongarch64/$bin"
done
test -f "$ROOT/build/out/initramfs/loongarch64/busybox.xz"
test -f "$ROOT/build/out/initramfs/loongarch64/vtchmod"
test -f "$ROOT/build/out/tools/loongarch64/ash"

echo "trixie outputs are in build/out. Pack with build/ci-centos.sh."
