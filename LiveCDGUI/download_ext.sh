#!/bin/sh
# Invoked as `sh ./download_ext.sh` from livecd.sh.
set -eu

date +"%Y/%m/%d %H:%M:%S"
echo downloading EXT files ...

# Last freely downloadable release. The porteus-kiosk.org copy of this ISO
# now returns 404; archive.org still has it.
ISO=Porteus-Kiosk-5.5.0-x86_64.iso
wget -q -P ./EXT/ "https://archive.org/download/porteus-kiosk-client/${ISO}"

rm -rf ./__tmp__
mkdir __tmp__

iso=$(readlink -f "./EXT/${ISO}")
loop=
cleanup() {
    if mountpoint -q ./__tmp__ 2>/dev/null; then
        umount ./__tmp__ || umount -l ./__tmp__ || true
    fi
    if [ -n "$loop" ]; then
        losetup -d "$loop" || true
    fi
}
trap cleanup EXIT

# trixie's mount sends a regular file through fsconfig. The GitHub runner
# kernel rejects that with "Can't lookup blockdev". The disk-image step in
# this job already attaches a loop device; do the same here.
loop=$(losetup -f --show -r "$iso")
if [ ! -b "$loop" ]; then
    spec=$(cat "/sys/class/block/${loop#/dev/}/dev")
    mknod -m 660 "$loop" b "${spec%%:*}" "${spec##*:}"
fi
mount -o ro "$loop" ./__tmp__
cp -a ./__tmp__/boot/vmlinuz ./EXT/
cp -a ./__tmp__/boot/initrd.xz ./EXT/
cp -a ./__tmp__/xzm/* ./EXT/
umount ./__tmp__
losetup -d "$loop"
loop=
rm -rf ./__tmp__
rm -f "$iso"
trap - EXIT

date +"%Y/%m/%d %H:%M:%S"
echo downloading EXT files finish ...
