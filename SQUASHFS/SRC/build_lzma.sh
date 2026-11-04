#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$XZ_URL" "xz-${XZ_VERSION}.tar.gz")

LIBDIR=$PWD/../LIB/LZMA

rm -rf $LIBDIR
rm -rf "xz-${XZ_VERSION}"
tar -xf "$archive"

cd "xz-${XZ_VERSION}"
./configure --prefix=$LIBDIR --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --enable-small
make -j 8 && make install

cd ..
rm -rf "xz-${XZ_VERSION}"

if [ -d $LIBDIR ]; then
    echo -e "\n========== SUCCESS ============\n"
else
    echo -e "\n========== FAILED ============\n"
fi


