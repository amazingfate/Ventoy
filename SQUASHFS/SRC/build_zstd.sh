#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$ZSTD_LIB_URL" "zstd-${ZSTD_LIB_VERSION}.tar.gz")

LIBDIR=$PWD/../LIB/ZSTD
ZSTDDIR=zstd-1.4.4

rm -rf $LIBDIR
rm -rf $ZSTDDIR
tar -xf "$archive"


cd $ZSTDDIR
PREFIX=$LIBDIR ZSTD_LIB_COMPRESSION=0 make
PREFIX=$LIBDIR ZSTD_LIB_COMPRESSION=0 make install

cd ..
rm -rf $ZSTDDIR

if [ -d $LIBDIR ]; then
    echo -e "\n========== SUCCESS ============\n"
else
    echo -e "\n========== FAILED ============\n"
fi

