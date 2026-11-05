#!/bin/sh
# Build the Linux installer tarball and the LiveCD ISO inside Debian trixie.
# Run as root in a privileged container so losetup, mkfs.vfat, and the
# LiveCD mount are available. GitHub Actions starts it from installers.yml.
#
#   docker run --rm --privileged -v "$PWD:/ventoy" -w /ventoy ventoy-trixie \
#       sh build/ci-release.sh

set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ "$(id -u)" -ne 0 ]; then
    echo "build/ci-release.sh needs root. Run it in privileged docker." >&2
    exit 1
fi

LOOP=
mnt=
cleanup() {
    if [ -n "${mnt:-}" ] && mountpoint -q "$mnt" 2>/dev/null; then
        umount "$mnt" || umount -l "$mnt" || true
    fi
    if [ -n "${LOOP:-}" ]; then
        losetup -d "$LOOP" || true
    fi
}
trap cleanup EXIT
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    git patch dos2unix file \
    dosfstools fdisk parted \
    squashfs-tools xorriso cpio xz-utils \
    bsdextrautils python3 \
    libgtk-3-dev pkg-config

echo "=== Linux web installers ==="
(
    cd "$ROOT/LinuxGUI"
    sh language.sh && sh build.sh
)
check_elf() {
    bin=$1
    needle=$2
    if [ ! -f "$bin" ]; then
        echo "missing $bin" >&2
        exit 1
    fi
    # Debian trixie file(1) says "Intel i386". Older file(1) says "Intel 80386".
    if ! file "$bin" | grep -E -q "$needle"; then
        echo "$bin is not $needle" >&2
        file "$bin" >&2
        exit 1
    fi
    echo "ok $bin"
}
check_elf "$ROOT/INSTALL/tool/x86_64/V2DServer" "x86-64"
check_elf "$ROOT/INSTALL/tool/i386/V2DServer" "i386|80386"
check_elf "$ROOT/INSTALL/tool/aarch64/V2DServer" "aarch64"
check_elf "$ROOT/INSTALL/tool/mips64el/V2DServer" "MIPS"

echo "=== GTK3 x86_64 ==="
( cd "$ROOT/LinuxGUI" && sh build_gtk.sh x86_64-gtk3 )
test -f "$ROOT/INSTALL/VentoyGUI.x86_64"
test -f "$ROOT/INSTALL/tool/x86_64/Ventoy2Disk.gtk3"

echo "=== VentoyVlnk.sh ==="
sh "$ROOT/Vlnk/pack.sh"
test -f "$ROOT/INSTALL/VentoyVlnk.sh"

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
test -f "$ROOT/INSTALL/EFI/BOOT/grubaa64_real.efi"
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
sh "$ROOT/build/build-efifs.sh" X64 IA32 AARCH64 LOONGARCH64
for short in x64 ia32 aa64 loongarch64; do
    test -f "$ROOT/build/out/efifs/iso9660_${short}.efi"
    test -f "$ROOT/build/out/efifs/udf_${short}.efi"
done

echo "=== initramfs tools ==="
sh "$ROOT/build/build-user.sh"
sh "$ROOT/build/build-init-busybox.sh"
for arch in x86_64 i386 aarch64 loongarch64 mips64el; do
    for bin in dmsetup unsquashfs vtoy_fuse_iso vtoytool vblade lunzip lz4cat zstdcat xzminidec; do
        test -f "$ROOT/build/out/tools/$arch/$bin"
    done
    test -f "$ROOT/build/out/initramfs/$arch/busybox.xz"
    test -f "$ROOT/build/out/initramfs/$arch/vtchmod"
done
test -f "$ROOT/build/out/tools/loongarch64/ash"
(
    cd "$ROOT/IMG"
    VTOY_CPIO_DEST="$ROOT/INSTALL/ventoy" bash ./mkcpio.sh
)
for cpio in ventoy.cpio ventoy_x86.cpio ventoy_arm64.cpio ventoy_mips64.cpio ventoy_loongarch64.cpio; do
    test -f "$ROOT/INSTALL/ventoy/$cpio"
done

echo "=== vtoycli ==="
# Non-destructive install asks vtoycli for the ESP length. Rebuild before the
# disk image is packed so the exfat helper copied onto the ESP matches.
(
    cd "$ROOT/vtoycli"
    build_vtoycli() {
        cc=$1
        lib=$2
        dest=$3
        shift 3
        # shellcheck disable=SC2086
        $cc "$@" -Os -no-pie -static -D_FILE_OFFSET_BITS=64 \
            vtoycli.c vtoyfat.c vtoygpt.c crc32.c partresize.c \
            -Ifat_io_lib/include "fat_io_lib/lib/$lib" \
            -o "$dest"
        stripbin=${cc%gcc}strip
        if [ "$cc" = "gcc" ]; then
            stripbin=strip
        fi
        if command -v "$stripbin" >/dev/null 2>&1; then
            "$stripbin" --strip-all "$dest"
        fi
        test -x "$dest"
    }
    build_vtoycli gcc libfat_io_64.a "$ROOT/INSTALL/tool/x86_64/vtoycli"
    build_vtoycli i686-linux-gnu-gcc libfat_io_32.a "$ROOT/INSTALL/tool/i386/vtoycli"
    build_vtoycli aarch64-linux-gnu-gcc libfat_io_aa64.a "$ROOT/INSTALL/tool/aarch64/vtoycli"
    build_vtoycli mips64el-linux-gnuabi64-gcc libfat_io_m64e.a "$ROOT/INSTALL/tool/mips64el/vtoycli" -mips64r2 -mabi=64
)

echo "=== installer disk image ==="
ver=$(sed -n 's/.*VENTOY_VERSION="\([^"]*\)".*/\1/p' "$ROOT/INSTALL/grub/grub.cfg" | head -1)
if [ -z "$ver" ]; then
    echo "VENTOY_VERSION is missing from INSTALL/grub/grub.cfg" >&2
    exit 1
fi

stage=$ROOT/build/out/ci-pack/stage
rm -rf "$ROOT/build/out/ci-pack"
# The installed ESP is 128 MiB. Copy modules and lists only; the prefix also
# contains unstripped .module objects that do not belong on the FAT volume.
mkdir -p "$stage/bios/i386-pc" "$stage/grub"
cp -a "$ROOT/INSTALL/grub/." "$stage/grub/"
for plat in i386-pc x86_64-efi i386-efi arm64-efi loongarch64-efi mips64el-efi; do
    src=$ROOT/build/out/prefix-$plat/lib/grub/$plat
    dest=$stage/grub/$plat
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src"/*.mod "$src"/*.lst "$dest/"
    test -f "$dest/normal.mod"
done
pc=$ROOT/build/out/prefix-i386-pc/lib/grub/i386-pc
cp -a "$pc"/*.mod "$pc"/*.lst "$pc"/*.img "$stage/bios/i386-pc/"
cp -a "$ROOT/build/out/images/core.img" "$stage/bios/i386-pc/core.img"
test -f "$stage/bios/i386-pc/boot.img"
test -f "$stage/bios/i386-pc/core.img"

img=$ROOT/build/out/ci-pack/img.bin
dd if=/dev/zero of="$img" bs=1M count=256 status=none
LOOP=$(losetup -f)
losetup -P "$LOOP" "$img"
i=0
while ! grep -q 524288 "/sys/block/${LOOP#/dev/}/size" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 30 ]; then
        echo "loop device $LOOP did not appear" >&2
        exit 1
    fi
    sleep 1
done

# ventoy_lib.sh uses expr, which exits 1 when the remainder is 0.
cd "$ROOT/build/out/ci-pack"
# shellcheck disable=SC1091
. "$ROOT/INSTALL/tool/ventoy_lib.sh"
set +e
format_ventoy_disk_mbr 0 "$LOOP" fdisk
fmt_status=$?
set -e
if [ "$fmt_status" -ne 0 ]; then
    echo "format_ventoy_disk_mbr failed" >&2
    exit 1
fi
if [ -z "${part2_start_sector:-}" ]; then
    echo "part2_start_sector was not set" >&2
    exit 1
fi
part2_sectors=$(cat "/sys/class/block/${LOOP#/dev/}p2/size")
if [ "$part2_sectors" != "262144" ]; then
    echo "ESP is $part2_sectors sectors, expected 262144 (128 MiB)" >&2
    exit 1
fi

# grub-bios-setup resolves the host directory to a block device. In Docker
# that directory is overlay or tmpfs, and the call exits 1 with
# "failed to get canonical path". grub-mkimage already points boot.img at
# sector 1 and core.img's block list at sector 2, which is the embedding gap
# before partition 1. Copy those bytes in and keep the partition table.
python3 - "$LOOP" "$stage/bios/i386-pc/boot.img" "$stage/bios/i386-pc/core.img" <<'PY'
import os, sys
dev, boot, core = sys.argv[1:]
b = bytearray(open(boot, "rb").read())
c = open(core, "rb").read()
if len(b) != 512:
    raise SystemExit("boot.img is not 512 bytes")
if len(c) > 2047 * 512:
    raise SystemExit("core.img does not fit in the embedding gap")
fd = os.open(dev, os.O_RDWR)
old = os.pread(fd, 512, 0)
# Same hard-disk drive-check NOP and BPB/partition preservation as
# grub-bios-setup. Bytes 0x1fe-0x1ff stay the boot.img signature.
b[0x03:0x5a] = old[0x03:0x5a]
b[0x66] = 0x90
b[0x67] = 0x90
b[0x1b8:0x1fe] = old[0x1b8:0x1fe]
os.pwrite(fd, bytes(b), 0)
os.pwrite(fd, c, 512)
os.fsync(fd)
os.close(fd)
print("BIOS boot sector installed")
PY

mnt=$ROOT/build/out/ci-pack/mnt
rm -rf "$mnt"
mkdir -p "$mnt"
mount "${LOOP}p2" "$mnt"

mkdir -p "$mnt/grub"
# vfat has no Unix owners. cp -a then exits 1 even though the bytes were written.
cp -a --no-preserve=ownership "$stage/grub/." "$mnt/grub/"
test -f "$mnt/grub/grub.cfg"
for plat in i386-pc x86_64-efi i386-efi arm64-efi loongarch64-efi mips64el-efi; do
    test -f "$mnt/grub/$plat/normal.mod"
done

(
    cd "$mnt/grub"
    tar czf help.tar.gz ./help/
    rm -rf ./help
    vtlangtitle=$(grep VTLANG_LANGUAGE_NAME menu/zh_CN.json | awk -F\" '{print $4}')
    echo "menuentry \"zh_CN  -  $vtlangtitle\" --class=menu_lang_item --class=debug_menu_lang --class=F5tool {" >> menulang.cfg
    echo "    vt_load_menu_lang zh_CN" >> menulang.cfg
    echo "}" >> menulang.cfg
    ls -1 menu/ | grep -v 'zh_CN' | sort | while read -r vtlang; do
        vtlangname=${vtlang%.*}
        vtlangtitle=$(grep VTLANG_LANGUAGE_NAME "menu/$vtlang" | awk -F\" '{print $4}')
        echo "menuentry \"$vtlangname  -  $vtlangtitle\" --class=menu_lang_item --class=debug_menu_lang --class=F5tool {" >> menulang.cfg
        echo "    vt_load_menu_lang $vtlangname" >> menulang.cfg
        echo "}" >> menulang.cfg
    done
    echo "menuentry \"\$VTLANG_RETURN_PREVIOUS\" --class=vtoyret VTOY_RET {" >> menulang.cfg
    echo "        echo \"Return ...\"" >> menulang.cfg
    echo "}" >> menulang.cfg
    tar czf menu.tar.gz ./menu/
    rm -rf ./menu
)
test -f "$mnt/grub/help.tar.gz"
test -f "$mnt/grub/menu.tar.gz"
rm -f "$mnt/grub/i386-pc/"*.img

cp -a --no-preserve=ownership "$ROOT/INSTALL/ventoy" "$mnt/"
cp -a --no-preserve=ownership "$ROOT/INSTALL/EFI" "$mnt/"
# INSTALL/EFI and INSTALL/ventoy still contain previously built files.
# Replace every boot file this run compiled.
install_built() {
    src=$1
    dest=$2
    if [ ! -f "$src" ]; then
        echo "missing built file $src" >&2
        exit 1
    fi
    cp -a --no-preserve=ownership "$src" "$dest"
}
imgdir=$ROOT/build/out/images
# BOOTX64.EFI is the Rocky shim copied with INSTALL/EFI. Do not replace it
# with GRUB. grubx64_real.efi is the image fbx64.efi chainloads.
install_built "$imgdir/grubx64_real.efi" "$mnt/EFI/BOOT/grubx64_real.efi"
if ! cmp -s "$ROOT/INSTALL/EFI/BOOT/BOOTX64.EFI" "$mnt/EFI/BOOT/BOOTX64.EFI"; then
    echo "ESP BOOTX64.EFI is not the Rocky shim" >&2
    exit 1
fi
# BOOTIA32.EFI is the Super-UEFIinSecureBoot-Disk shim copied with
# INSTALL/EFI. Do not replace it with GRUB. grubia32.efi chainloads
# grubia32_real.efi.
install_built "$imgdir/grubia32_real.efi" "$mnt/EFI/BOOT/grubia32_real.efi"
if ! cmp -s "$ROOT/INSTALL/EFI/BOOT/BOOTIA32.EFI" "$mnt/EFI/BOOT/BOOTIA32.EFI"; then
    echo "ESP BOOTIA32.EFI is not the upstream shim" >&2
    exit 1
fi
if ! cmp -s "$ROOT/INSTALL/EFI/BOOT/grubia32.efi" "$mnt/EFI/BOOT/grubia32.efi"; then
    echo "ESP grubia32.efi is not the upstream loader" >&2
    exit 1
fi
install_built "$imgdir/BOOTAA64.EFI" "$mnt/EFI/BOOT/BOOTAA64.EFI"
install_built "$imgdir/BOOTLOONGARCH64.EFI" "$mnt/EFI/BOOT/BOOTLOONGARCH64.EFI"
install_built "$imgdir/BOOTMIPS.EFI" "$mnt/EFI/BOOT/BOOTMIPS.EFI"
install_built "$imgdir/BOOTMIPS.EFI" "$mnt/EFI/BOOT/BOOTMIPS64EL.EFI"
edk=$ROOT/build/out/edk2
install_built "$edk/X64/Ventoy.efi" "$mnt/ventoy/ventoy_x64.efi"
install_built "$edk/X64/VtoyUtil.efi" "$mnt/ventoy/vtoyutil_x64.efi"
install_built "$edk/IA32/Ventoy.efi" "$mnt/ventoy/ventoy_ia32.efi"
install_built "$edk/IA32/VtoyUtil.efi" "$mnt/ventoy/vtoyutil_ia32.efi"
install_built "$edk/AARCH64/Ventoy.efi" "$mnt/ventoy/ventoy_aa64.efi"
install_built "$edk/AARCH64/VtoyUtil.efi" "$mnt/ventoy/vtoyutil_aa64.efi"
install_built "$edk/LOONGARCH64/Ventoy.efi" "$mnt/ventoy/ventoy_loongarch64.efi"
install_built "$edk/LOONGARCH64/VtoyUtil.efi" "$mnt/ventoy/vtoyutil_loongarch64.efi"
efs=$ROOT/build/out/efifs
for short in x64 ia32 aa64 loongarch64; do
    install_built "$efs/iso9660_${short}.efi" "$mnt/ventoy/iso9660_${short}.efi"
    install_built "$efs/udf_${short}.efi" "$mnt/ventoy/udf_${short}.efi"
done
for cpio in ventoy.cpio ventoy_x86.cpio ventoy_arm64.cpio ventoy_mips64.cpio ventoy_loongarch64.cpio; do
    test -f "$mnt/ventoy/$cpio"
done
test -f "$mnt/EFI/BOOT/grubx64_real.efi"
test -f "$mnt/EFI/BOOT/grubia32_real.efi"
test -f "$mnt/EFI/BOOT/grubaa64_real.efi"
test -f "$mnt/EFI/BOOT/fbx64.efi"
test -f "$mnt/EFI/BOOT/fbia32.efi"
test -f "$mnt/EFI/BOOT/fbaa64.efi"

mkdir -p "$mnt/tool"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/i386/vtoycli" of="$mnt/tool/mount.exfat-fuse_i386"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/x86_64/vtoycli" of="$mnt/tool/mount.exfat-fuse_x86_64"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/aarch64/vtoycli" of="$mnt/tool/mount.exfat-fuse_aarch64"
cp -a --no-preserve=ownership "$ROOT/INSTALL/tool/create_ventoy_iso_part_dm.sh" "$mnt/tool/"
if [ -f "$ROOT/INSTALL/tool/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" ]; then
    cp -a --no-preserve=ownership "$ROOT/INSTALL/tool/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" "$mnt/"
fi

# BOOTX64.EFI is already signed by Microsoft and must not be signed again.
# VtoyShim checks the on-disk GRUB hash, so sign grub*_real.efi first.
# Without VENTOY_CERT_KEY and VENTOY_CERT_PEM this is the same NO-CA path
# as INSTALL/ventoy_pack.sh.
sign_efi() {
    efi=$1
    if [ ! -f "$efi" ]; then
        echo "### $efi non-exist"
        return 0
    fi
    if [ -z "${VENTOY_CERT_KEY:-}" ] || [ -z "${VENTOY_CERT_PEM:-}" ]; then
        echo "### $efi NO-CA"
        return 0
    fi
    if ! command -v sbsign >/dev/null 2>&1; then
        apt-get install -y --no-install-recommends sbsigntool
    fi
    rm -f "${efi}.signed"
    sbsign --key "$VENTOY_CERT_KEY" --cert "$VENTOY_CERT_PEM" --output "${efi}.signed" "$efi"
    mv "${efi}.signed" "$efi"
    echo "### $efi signed"
}

# Each shim's placeholder becomes the hash of the GRUB image it loads.
inject_grub_hash() {
    shim=$1
    grub=$2
    grub_sha256=$(sha256sum "$mnt/EFI/BOOT/$grub" | awk '{print $1}')
    magic_cnt=$(hexdump -C "$mnt/EFI/BOOT/$shim" | grep -c '26 26 26 26 26 26 26 26' || true)
    if [ "$magic_cnt" -ne 1 ]; then
        echo "$shim hash placeholder count is $magic_cnt, expected 1" >&2
        exit 1
    fi
    magic_off_hex=$(hexdump -C "$mnt/EFI/BOOT/$shim" | grep '26 26 26 26 26 26 26 26' | awk '{print $1}')
    magic_off=$(printf '%u' "0x${magic_off_hex}")
    echo "$shim <- $grub $grub_sha256"
    hashbin=$ROOT/build/out/ci-pack/grub.sha256
    python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$grub_sha256" > "$hashbin"
    dd if="$hashbin" bs=1 count=32 of="$mnt/EFI/BOOT/$shim" seek="$magic_off" conv=notrunc status=none
}
sign_efi "$mnt/EFI/BOOT/grubx64_real.efi"
sign_efi "$mnt/EFI/BOOT/grubia32_real.efi"
sign_efi "$mnt/EFI/BOOT/grubaa64_real.efi"
inject_grub_hash fbx64.efi grubx64_real.efi
inject_grub_hash fbia32.efi grubia32_real.efi
inject_grub_hash fbaa64.efi grubaa64_real.efi
sign_efi "$mnt/EFI/BOOT/fbx64.efi"
sign_efi "$mnt/EFI/BOOT/fbia32.efi"
sign_efi "$mnt/EFI/BOOT/fbaa64.efi"

sync
umount "$mnt"
mnt=

pkg=$ROOT/build/out/ci-pack/ventoy-$ver
rm -rf "$pkg"
mkdir -p "$pkg/boot" "$pkg/ventoy"
echo "$ver" > "$pkg/ventoy/version"
dd if="$LOOP" of="$pkg/boot/boot.img" bs=1 count=512 status=none
dd if="$LOOP" of="$pkg/boot/core.img" bs=512 count=2047 skip=1 status=none
xz --check=crc32 "$pkg/boot/core.img"
dd if="$LOOP" of="$pkg/ventoy/ventoy.disk.img" bs=512 count="$VENTOY_SECTOR_NUM" skip="$part2_start_sector" status=none
img_bytes=$(stat -c '%s' "$pkg/ventoy/ventoy.disk.img")
if [ "$img_bytes" != "134217728" ]; then
    echo "ventoy.disk.img is $img_bytes bytes, expected 134217728 (128 MiB)" >&2
    exit 1
fi
xz --check=crc32 "$pkg/ventoy/ventoy.disk.img"

losetup -d "$LOOP"
LOOP=

echo "=== linux tarball ==="
cp -a "$ROOT/INSTALL/tool" "$pkg/"
rm -f "$pkg/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
cp -a "$ROOT/INSTALL/Ventoy2Disk.sh" "$pkg/"
cp -a "$ROOT/INSTALL/VentoyWeb.sh" "$pkg/"
cp -a "$ROOT/INSTALL/VentoyPlugson.sh" "$pkg/"
cp -a "$ROOT/INSTALL/VentoyVlnk.sh" "$pkg/"
cp -a "$ROOT/INSTALL/VentoyGUI."* "$pkg/" 2>/dev/null || true
cp -a "$ROOT/INSTALL/README" "$pkg/"
cp -a "$ROOT/INSTALL/plugin" "$pkg/"
cp -a "$ROOT/INSTALL/CreatePersistentImg.sh" "$pkg/"
cp -a "$ROOT/INSTALL/ExtendPersistentImg.sh" "$pkg/"
dos2unix -q "$pkg/Ventoy2Disk.sh" "$pkg/VentoyWeb.sh" "$pkg/VentoyPlugson.sh" "$pkg/VentoyVlnk.sh"
dos2unix -q "$pkg/CreatePersistentImg.sh" "$pkg/ExtendPersistentImg.sh"
cp -a "$ROOT/LinuxGUI/WebUI" "$pkg/"
sed 's/.*SCRIPT_DEL_THIS \(.*\)/\1/g' -i "$pkg/WebUI/index.html"
cp -a "$ROOT/LANGUAGES/languages.json" "$pkg/tool/"

for d in i386 x86_64 aarch64 mips64el; do
    for file in "$pkg/tool/$d"/*; do
        name=$(basename "$file")
        if [ "$name" = "xzcat" ]; then
            continue
        fi
        case "$name" in
            Ventoy2Disk*) chmod +x "$file" ;;
            *) xz --check=crc32 "$file" ;;
        esac
    done
done

find "$pkg" -type d -exec chmod 755 "{}" +
find "$pkg" -type f -exec chmod 644 "{}" +
chmod +x "$pkg/Ventoy2Disk.sh" "$pkg/VentoyWeb.sh" "$pkg/VentoyPlugson.sh" "$pkg/VentoyVlnk.sh"
chmod +x "$pkg/tool/"*.sh
for gui in "$pkg"/VentoyGUI*; do
    if [ -f "$gui" ]; then
        chmod +x "$gui"
    fi
done
for d in i386 x86_64 aarch64 mips64el; do
    chmod +x "$pkg/tool/$d/xzcat"
    for exe in "$pkg/tool/$d"/Ventoy2Disk.*; do
        if [ -f "$exe" ]; then
            chmod +x "$exe"
        fi
    done
done

rm -f "$ROOT/INSTALL/ventoy-${ver}-linux.tar.gz"
tar -czf "$ROOT/INSTALL/ventoy-${ver}-linux.tar.gz" -C "$ROOT/build/out/ci-pack" "ventoy-${ver}"
test -f "$ROOT/INSTALL/ventoy-${ver}-linux.tar.gz"

echo "=== LiveCD ISO ==="
(
    cd "$ROOT/LiveCDGUI"
    bash ./livecd.sh CI
)
test -f "$ROOT/LiveCDGUI/ventoy-${ver}-livecd.iso"
iso_bytes=$(stat -c '%s' "$ROOT/LiveCDGUI/ventoy-${ver}-livecd.iso")
if [ "$iso_bytes" -lt 1000000 ]; then
    echo "LiveCD ISO is only $iso_bytes bytes" >&2
    exit 1
fi

if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    chown "$HOST_UID:$HOST_GID" \
        "$ROOT/INSTALL/ventoy-${ver}-linux.tar.gz" \
        "$ROOT/LiveCDGUI/ventoy-${ver}-livecd.iso" || true
    chown -R "$HOST_UID:$HOST_GID" \
        "$ROOT/INSTALL/EFI" \
        "$ROOT/INSTALL/tool" \
        "$ROOT/LiveCD/GRUB" \
        "$ROOT/LiveCDGUI/GRUB" \
        "$ROOT/LiveCDGUI/EXT" || true
fi

echo "linux installer: INSTALL/ventoy-${ver}-linux.tar.gz"
echo "livecd iso:      LiveCDGUI/ventoy-${ver}-livecd.iso"
ls -lh "$ROOT/INSTALL/ventoy-${ver}-linux.tar.gz" "$ROOT/LiveCDGUI/ventoy-${ver}-livecd.iso"
