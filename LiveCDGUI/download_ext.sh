#!/bin/bash

date +"%Y/%m/%d %H:%M:%S"
echo downloading EXT files ...

# Last freely downloadable release. The porteus-kiosk.org copy of this ISO
# now returns 404; archive.org still has it.
ISO=Porteus-Kiosk-5.5.0-x86_64.iso
wget -q -P ./EXT/ "https://archive.org/download/porteus-kiosk-client/${ISO}"

[ -d ./__tmp__ ] && rm -rf ./__tmp__
mkdir __tmp__

mount ./EXT/${ISO} ./__tmp__
cp -a ./__tmp__/boot/vmlinuz   ./EXT/
cp -a ./__tmp__/boot/initrd.xz ./EXT/
cp -a ./__tmp__/xzm/* ./EXT/

umount ./__tmp__
rm -rf ./__tmp__
rm -f ./EXT/${ISO}

date +"%Y/%m/%d %H:%M:%S"
echo downloading EXT files finish ...

