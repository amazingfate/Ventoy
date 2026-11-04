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
    if ! file "$bin" | grep -q "$needle"; then
        echo "$bin is not $needle" >&2
        file "$bin" >&2
        exit 1
    fi
    echo "ok $bin"
}
check_elf "$ROOT/INSTALL/tool/x86_64/V2DServer" "x86-64"
check_elf "$ROOT/INSTALL/tool/i386/V2DServer" "80386"
check_elf "$ROOT/INSTALL/tool/aarch64/V2DServer" "aarch64"
check_elf "$ROOT/INSTALL/tool/mips64el/V2DServer" "MIPS"

echo "=== GTK3 x86_64 ==="
( cd "$ROOT/LinuxGUI" && sh build_gtk.sh x86_64-gtk3 )
test -f "$ROOT/INSTALL/VentoyGUI.x86_64"
test -f "$ROOT/INSTALL/tool/x86_64/Ventoy2Disk.gtk3"

echo "=== VentoyVlnk.sh ==="
sh "$ROOT/Vlnk/pack.sh"
test -f "$ROOT/INSTALL/VentoyVlnk.sh"

echo "=== GRUB x86_64-efi and i386-pc ==="
sh "$ROOT/build/build-grub.sh" x86_64-efi i386-pc
test -f "$ROOT/build/out/images/core.img"
test -f "$ROOT/build/out/prefix-i386-pc/sbin/grub-bios-setup"
test -f "$ROOT/INSTALL/EFI/BOOT/grubx64_real.efi"
test -f "$ROOT/LiveCDGUI/GRUB/bootx64.efi"
test -f "$ROOT/LiveCDGUI/GRUB/cdrom.img"

echo "=== EDK2 X64 shim (fbx64.efi) ==="
sh "$ROOT/build/build-edk2.sh" X64
test -f "$ROOT/INSTALL/EFI/BOOT/fbx64.efi"

echo "=== installer disk image ==="
ver=$(sed -n 's/.*VENTOY_VERSION="\([^"]*\)".*/\1/p' "$ROOT/INSTALL/grub/grub.cfg" | head -1)
if [ -z "$ver" ]; then
    echo "VENTOY_VERSION is missing from INSTALL/grub/grub.cfg" >&2
    exit 1
fi

stage=$ROOT/build/out/ci-pack/stage
rm -rf "$ROOT/build/out/ci-pack"
# The installed ESP is 32 MiB. Copy modules and lists only; the prefix also
# contains unstripped .module objects that do not fit.
pc=$ROOT/build/out/prefix-i386-pc/lib/grub/i386-pc
efi=$ROOT/build/out/prefix-x86_64-efi/lib/grub/x86_64-efi
mkdir -p "$stage/bios/i386-pc" "$stage/grub/i386-pc" "$stage/grub/x86_64-efi"
cp -a "$ROOT/INSTALL/grub/." "$stage/grub/"
cp -a "$pc"/*.mod "$pc"/*.lst "$stage/grub/i386-pc/"
cp -a "$efi"/*.mod "$efi"/*.lst "$stage/grub/x86_64-efi/"
cp -a "$pc"/*.mod "$pc"/*.lst "$pc"/*.img "$stage/bios/i386-pc/"
cp -a "$ROOT/build/out/images/core.img" "$stage/bios/i386-pc/core.img"
test -f "$stage/bios/i386-pc/boot.img"
test -f "$stage/bios/i386-pc/core.img"
test -f "$stage/grub/i386-pc/normal.mod"
test -f "$stage/grub/x86_64-efi/normal.mod"

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

"$ROOT/build/out/prefix-i386-pc/sbin/grub-bios-setup" \
    --skip-fs-probe \
    --directory="$stage/bios/i386-pc" \
    "$LOOP"

mnt=$ROOT/build/out/ci-pack/mnt
rm -rf "$mnt"
mkdir -p "$mnt"
mount "${LOOP}p2" "$mnt"

mkdir -p "$mnt/grub"
cp -a "$stage/grub/grub.cfg" "$mnt/grub/"
# vfat rejects owner preservation. The copy still writes the files.
cp -a "$stage/grub/." "$mnt/grub/" || true
test -f "$mnt/grub/grub.cfg"
test -f "$mnt/grub/i386-pc/normal.mod"
test -f "$mnt/grub/x86_64-efi/normal.mod"

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

cp -a "$ROOT/INSTALL/ventoy" "$mnt/" || true
cp -a "$ROOT/INSTALL/EFI" "$mnt/" || true
test -f "$mnt/EFI/BOOT/BOOTX64.EFI"
test -f "$mnt/EFI/BOOT/grubx64_real.efi"
test -f "$mnt/EFI/BOOT/fbx64.efi"
test -f "$mnt/ventoy/ventoy_x64.efi"

mkdir -p "$mnt/tool"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/i386/vtoycli" of="$mnt/tool/mount.exfat-fuse_i386"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/x86_64/vtoycli" of="$mnt/tool/mount.exfat-fuse_x86_64"
dd status=none bs=1024 count=16 if="$ROOT/INSTALL/tool/aarch64/vtoycli" of="$mnt/tool/mount.exfat-fuse_aarch64"
cp -a "$ROOT/INSTALL/tool/create_ventoy_iso_part_dm.sh" "$mnt/tool/"
cp -a "$ROOT/INSTALL/tool/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" "$mnt/" || true

# Secure Boot signing stays off unless VENTOY_CERT_KEY and VENTOY_CERT_PEM
# are provided. The placeholder in fbx64.efi still has to become the hash of
# this disk's grubx64_real.efi.
grub_sha256=$(sha256sum "$mnt/EFI/BOOT/grubx64_real.efi" | awk '{print $1}')
magic_cnt=$(hexdump -C "$mnt/EFI/BOOT/fbx64.efi" | grep -c '26 26 26 26 26 26 26 26' || true)
if [ "$magic_cnt" -ne 1 ]; then
    echo "fbx64.efi hash placeholder count is $magic_cnt, expected 1" >&2
    exit 1
fi
magic_off_hex=$(hexdump -C "$mnt/EFI/BOOT/fbx64.efi" | grep '26 26 26 26 26 26 26 26' | awk '{print $1}')
magic_off=$(printf '%u' "0x${magic_off_hex}")
echo "Ventoy Grub hash $grub_sha256"
hashbin=$ROOT/build/out/ci-pack/grub.sha256
python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$grub_sha256" > "$hashbin"
dd if="$hashbin" bs=1 count=32 of="$mnt/EFI/BOOT/fbx64.efi" seek="$magic_off" conv=notrunc status=none

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
