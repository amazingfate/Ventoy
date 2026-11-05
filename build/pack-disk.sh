#!/bin/sh
# Assemble a Ventoy disk image from build/out and the INSTALL payload.
# No root and no loop device: partitions are written with sfdisk and mtools.
# Usage: build/pack-disk.sh
# Output: build/out/ventoy.img

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/out"
WORK="$ROOT/build/work/disk"
STAGE="$WORK/stage"
IMG="$OUT/ventoy.img"

GAP=2048
# 3 GiB exFAT for the ISO files. Three Debian netinst images are about 2.2 GiB.
DATA_SECTORS=$((3 * 1024 * 2048))
# 128 MiB ESP, the same size the installer writes. GRUB still accepts a 32 MiB ESP.
ESP_SECTORS=262144
P1=$GAP
P2=$((GAP + DATA_SECTORS))
# FAT32 on this size has 258077 free clusters. Leave the directory entries some room.
BUDGET=$((258077 * 512 - 256 * 1024))

rm -rf "$STAGE"
mkdir -p "$STAGE/EFI/BOOT" "$STAGE/grub" "$STAGE/ventoy" "$WORK"

cp -a "$ROOT/INSTALL/grub/." "$STAGE/grub/"

copy_mods() {
    plat=$1
    src="$OUT/prefix-$plat/lib/grub/$plat"
    dest="$STAGE/grub/$plat"
    if [ ! -d "$src" ]; then
        echo "pack-disk: no $plat modules, skipping"
        return 0
    fi
    mkdir -p "$dest"
    find "$src" -maxdepth 1 -type f \( -name '*.mod' -o -name '*.lst' -o -name '*.img' \) -exec cp -a {} "$dest/" \;
}

# x86 BIOS and both UEFI firmwares always go in, with their full module sets.
copy_mods x86_64-efi
copy_mods i386-efi
copy_mods i386-pc

copy_efi() {
    name=$1
    src=$2
    if [ -f "$src" ]; then
        cp -a "$src" "$STAGE/EFI/BOOT/$name"
    else
        echo "pack-disk: no $name"
    fi
}

stage_bytes() {
    du -sb "$STAGE" | awk '{print $1}'
}

# BOOTX64.EFI is the signed Rocky shim. GRUB is grubx64_real.efi.
copy_efi BOOTX64.EFI "$ROOT/INSTALL/EFI/BOOT/BOOTX64.EFI"
copy_efi mmx64.efi "$ROOT/INSTALL/EFI/BOOT/mmx64.efi"
copy_efi fbx64.efi "$ROOT/INSTALL/EFI/BOOT/fbx64.efi"
copy_efi grubx64_real.efi "$ROOT/INSTALL/EFI/BOOT/grubx64_real.efi"
# BOOTIA32.EFI is the Super-UEFIinSecureBoot-Disk shim. The shim loads
# grubia32.efi, which chainloads grubia32_real.efi.
copy_efi BOOTIA32.EFI "$ROOT/INSTALL/EFI/BOOT/BOOTIA32.EFI"
copy_efi grubia32.efi "$ROOT/INSTALL/EFI/BOOT/grubia32.efi"
copy_efi mmia32.efi "$ROOT/INSTALL/EFI/BOOT/mmia32.efi"
copy_efi grubia32_real.efi "$ROOT/INSTALL/EFI/BOOT/grubia32_real.efi"

# Payload that is still shipped as data (Windows boot files, memdisk, ipxe).
# EFI applications built in this tree replace the matching prebuilt files.
find "$ROOT/INSTALL/ventoy" -maxdepth 1 -type f -exec cp -a {} "$STAGE/ventoy/" \;

place_efi() {
    dest=$1
    src=$2
    if [ -f "$src" ]; then
        cp -a "$src" "$STAGE/ventoy/$dest"
    fi
}

place_efi ventoy_x64.efi "$OUT/edk2/X64/Ventoy.efi"
place_efi vtoyutil_x64.efi "$OUT/edk2/X64/VtoyUtil.efi"
place_efi ventoy_aa64.efi "$OUT/edk2/AARCH64/Ventoy.efi"
place_efi vtoyutil_aa64.efi "$OUT/edk2/AARCH64/VtoyUtil.efi"
place_efi ventoy_loongarch64.efi "$OUT/edk2/LOONGARCH64/Ventoy.efi"
place_efi vtoyutil_loongarch64.efi "$OUT/edk2/LOONGARCH64/VtoyUtil.efi"
place_efi iso9660_x64.efi "$OUT/efifs/iso9660_x64.efi"
place_efi udf_x64.efi "$OUT/efifs/udf_x64.efi"
place_efi iso9660_ia32.efi "$OUT/efifs/iso9660_ia32.efi"
place_efi udf_ia32.efi "$OUT/efifs/udf_ia32.efi"
place_efi iso9660_aa64.efi "$OUT/efifs/iso9660_aa64.efi"
place_efi udf_aa64.efi "$OUT/efifs/udf_aa64.efi"
place_efi iso9660_loongarch64.efi "$OUT/efifs/iso9660_loongarch64.efi"
place_efi udf_loongarch64.efi "$OUT/efifs/udf_loongarch64.efi"

(
    cd "$ROOT/IMG"
    VTOY_CPIO_DEST="$OUT/cpio" bash mkcpio.sh
)
find "$OUT/cpio" -maxdepth 1 -type f -name 'ventoy*.cpio' -exec cp -a {} "$STAGE/ventoy/" \;

copy_boot() {
    name=$1
    if [ -f "$OUT/images/$name" ]; then
        cp -a "$OUT/images/$name" "$STAGE/EFI/BOOT/$name"
    fi
}

# Modules the menu loads on top of the ones already built into BOOT*.EFI.
copy_menu_mods() {
    plat=$1
    src="$OUT/prefix-$plat/lib/grub/$plat"
    dest="$STAGE/grub/$plat"
    if [ ! -d "$src" ]; then
        return 0
    fi
    mkdir -p "$dest"
    for mod in gfxterm png jpeg gettext all_video font gfxmenu video video_fb \
        gfxterm_background gfxterm_menu bitmap bitmap_scale trig video_colors bufio \
        tar ls cat halt reboot sleep probe chain setkey regexp; do
        if [ -f "$src/$mod.mod" ]; then
            cp -a "$src/$mod.mod" "$dest/"
        fi
    done
    find "$src" -maxdepth 1 -type f -name '*.lst' -exec cp -a {} "$dest/" \;
}

# Keep the menu modules if the full tree does not fit.
upgrade_full() {
    plat=$1
    src="$OUT/prefix-$plat/lib/grub/$plat"
    dest="$STAGE/grub/$plat"
    mark="$WORK/upgrade-$plat"
    if [ ! -d "$src" ]; then
        return 0
    fi
    mkdir -p "$dest"
    : > "$mark"
    find "$src" -maxdepth 1 -type f \( -name '*.mod' -o -name '*.img' \) | while read -r srcfile; do
        base=$(basename "$srcfile")
        if [ ! -f "$dest/$base" ]; then
            cp -a "$srcfile" "$dest/$base"
            echo "$base" >> "$mark"
        fi
    done
    if [ "$(stage_bytes)" -gt "$BUDGET" ]; then
        while IFS= read -r base; do
            rm -f "$dest/$base"
        done < "$mark"
        echo "pack-disk: $plat keeps the menu modules"
    else
        echo "pack-disk: $plat includes the full module set"
    fi
    rm -f "$mark"
}

copy_boot BOOTAA64.EFI
copy_boot BOOTLOONGARCH64.EFI
copy_boot BOOTMIPS.EFI
if [ -f "$STAGE/EFI/BOOT/BOOTMIPS.EFI" ]; then
    cp -a "$STAGE/EFI/BOOT/BOOTMIPS.EFI" "$STAGE/EFI/BOOT/BOOTMIPS64EL.EFI"
fi
for plat in loongarch64-efi arm64-efi mips64el-efi; do
    copy_menu_mods "$plat"
done
# Full trees are about 8.0, 6.1 and 8.1 MiB. The 128 MiB FAT32 holds all three.
for plat in loongarch64-efi arm64-efi mips64el-efi; do
    upgrade_full "$plat"
done

echo "pack-disk: staged $(stage_bytes) bytes"

ESP="$WORK/esp.img"
DATA="$WORK/data.img"
rm -f "$ESP" "$DATA" "$IMG"
truncate -s $((ESP_SECTORS * 512)) "$ESP"
truncate -s $((DATA_SECTORS * 512)) "$DATA"
# 128 MiB is a real FAT32. A 32 MiB FAT32 is rejected by OVMF.
mkfs.vfat -F 32 -n VTOYEFI "$ESP"
mkfs.exfat -n Ventoy "$DATA" >/dev/null

mcopy -i "$ESP" -s "$STAGE/EFI" "$STAGE/grub" "$STAGE/ventoy" ::/

truncate -s $(( (P2 + ESP_SECTORS) * 512 )) "$IMG"
sfdisk "$IMG" <<EOF
label: dos
unit: sectors
start=${P1}, size=${DATA_SECTORS}, type=7
start=${P2}, size=${ESP_SECTORS}, type=ef, bootable
EOF
dd if="$DATA" of="$IMG" bs=512 seek="$P1" conv=notrunc status=none
dd if="$ESP" of="$IMG" bs=512 seek="$P2" conv=notrunc status=none

PC="$OUT/prefix-i386-pc/lib/grub/i386-pc"
if [ -f "$OUT/images/core.img" ] && [ -f "$PC/boot.img" ]; then
    # boot.img already names sector 1, and core.img's block list starts at
    # sector 2. grub-bios-setup refuses a regular file and probes the host disk.
    python3 - "$IMG" "$PC/boot.img" "$OUT/images/core.img" <<'PY'
import sys
img, boot, core = sys.argv[1:]
disk = bytearray(open(img, "rb").read())
b = open(boot, "rb").read()
c = open(core, "rb").read()
if len(c) > 2047 * 512:
    raise SystemExit("core.img does not fit in the 1 MiB embedding gap")
disk[0:446] = b[0:446]
disk[512:512 + len(c)] = c
open(img, "wb").write(disk)
print("pack-disk: BIOS boot sector installed")
PY
else
    echo "pack-disk: i386-pc is not built, BIOS boot sector left empty"
fi

echo "pack-disk: $IMG"
ls -lh "$IMG"
