#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$VBLADE_URL" "vblade-${VBLADE_VERSION}.tar.gz")

src="$ROOT/build/work/vblade-host"
rm -rf "$src"
mkdir -p "$src"
tar -xf "$archive" -C "$src" --strip-components=1
patch -p1 -d "$src" < "$ROOT/build/patches/vblade/0001-ventoy-vblade.patch"

rm -f vblade_*
gcc "$src/linux.c" "$src/aoe.c" "$src/ata.c" "$src/bpf.c" -Os -o vblade_64
gcc "$src/linux.c" "$src/aoe.c" "$src/ata.c" "$src/bpf.c" -Os -m32 -o vblade_32
aarch64-buildroot-linux-uclibc-gcc "$src/linux.c" "$src/aoe.c" "$src/ata.c" "$src/bpf.c" -Os -static -o vblade_aa64

if [ -e vblade_64 ] && [ -e vblade_32 ] && [ -e vblade_aa64 ]; then
    echo -e '\n################## SUCCESS ######################\n'
else
    echo -e '\n################## FAILED ######################\n'
    exit 1
fi
