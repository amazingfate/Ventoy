#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$LZO_URL" "lzo-${LZO_VERSION}.tar.gz")

LIBDIR=$PWD/../LIB/LZO
LZODIR=lzo-2.08

rm -rf $LIBDIR
rm -rf $LZODIR
tar -xf "$archive"


cd $LZODIR
./configure --prefix=$LIBDIR --disable-shared

make && make install

cd ..
rm -rf $LZODIR

if [ -d $LIBDIR ]; then
    echo -e "\n========== SUCCESS ============\n"
else
    echo -e "\n========== FAILED ============\n"
fi

