#!/bin/sh

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$FAT_IO_URL" "fat_io_lib-${FAT_IO_COMMIT}.tar.gz")

cd "$ROOT/vtoyfat/fat_io_lib"
rm -rf "fat_io_lib-${FAT_IO_COMMIT}"
tar -xf "$archive"

rm -rf include
rm -rf lib


cd "fat_io_lib-${FAT_IO_COMMIT}/src"
gcc -O2 -D_FILE_OFFSET_BITS=64 fat*.c -c
ar -rc libfat_io_64.a *.o
rm -f *.o


gcc -m32 -O2 -D_FILE_OFFSET_BITS=64 fat*.c -c
ar -rc libfat_io_32.a *.o
rm -f *.o


aarch64-linux-gnu-gcc -O2 -D_FILE_OFFSET_BITS=64 fat*.c -c
ar -rc libfat_io_aa64.a *.o
rm -f *.o


mips64el-linux-musl-gcc -mips64r2 -mabi=64 -O2 -D_FILE_OFFSET_BITS=64 fat*.c -c
ar -rc libfat_io_m64e.a *.o
rm -f *.o

cd "$ROOT/vtoyfat/fat_io_lib"


mkdir lib
mkdir include

mv "fat_io_lib-${FAT_IO_COMMIT}/src/"*.a lib/
cp -a "fat_io_lib-${FAT_IO_COMMIT}/src/"*.h include/
rm -rf "fat_io_lib-${FAT_IO_COMMIT}"


