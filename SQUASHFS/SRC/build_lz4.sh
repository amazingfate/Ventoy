#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$LZ4_URL" "lz4-${LZ4_VERSION}.tar.gz")

LIBDIR=$PWD/../LIB/LZ4

rm -rf $LIBDIR
rm -rf lz4-1.8.1.2
tar -xf "$archive"


cd lz4-1.8.1.2
make && PREFIX=$LIBDIR make install

cd ..
rm -rf lz4-1.8.1.2

if [ -d $LIBDIR ]; then
    echo -e "\n========== SUCCESS ============\n"
else
    echo -e "\n========== FAILED ============\n"
fi


