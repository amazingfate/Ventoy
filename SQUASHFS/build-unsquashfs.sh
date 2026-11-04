#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$SQUASHFS_URL" "squashfs-tools-${SQUASHFS_VERSION}.tar.gz")

src="$ROOT/build/work/squashfs-host"
rm -rf "$src"
mkdir -p "$src"
tar -xf "$archive" -C "$src" --strip-components=1
patch -p1 -d "$src" < "$ROOT/build/patches/squashfs/0001-ventoy-squashfs.patch"

export LZMA_LIBDIR=$ROOT/SQUASHFS/LIB/LZMA
export LZ4_LIBDIR=$ROOT/SQUASHFS/LIB/LZ4
export ZSTD_LIBDIR=$ROOT/SQUASHFS/LIB/ZSTD
export LZO_LIBDIR=$ROOT/SQUASHFS/LIB/LZO

if [ -e /lib64/libz.a ]; then
    export VTZLIB=/lib64/libz.a
elif [ -e /lib/libz.a ]; then
    export VTZLIB=/lib/libz.a
elif [ -e /usr/lib/libz.a ]; then
    export VTZLIB=/usr/lib/libz.a
fi

cd "$src/squashfs-tools"
rm -f unsquashfs
make clean
make -e unsquashfs

if [ -e unsquashfs ]; then
    strip --strip-all unsquashfs
    echo -e "\n========== SUCCESS ============\n"
else
    echo -e "\n========== FAILED ============\n"
    exit 1
fi

if uname -a | egrep -q 'x86_64|amd64'; then
    name=unsquashfs_64
elif uname -a | egrep -q 'aarch64'; then
    name=unsquashfs_aa64
else
    name=unsquashfs_32
fi

rm -f "$ROOT/SQUASHFS/$name"
cp -a unsquashfs "$ROOT/SQUASHFS/$name"
