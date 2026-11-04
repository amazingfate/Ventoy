#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/build/versions.env"
archive=$("$ROOT/build/download.sh" "$IPXE_URL" "ipxe-${IPXE_COMMIT}.tar.gz")

cd "$ROOT/IPXE"
rm -rf ipxe-3fe683e
tar -xf "$archive" -C ./
mv "ipxe-${IPXE_COMMIT}" ipxe-3fe683e

rm -rf ./ipxe-3fe683e/src/bin
rm -rf ./ipxe-3fe683e/src/drivers

/bin/cp -a ipxe_mod_code/ipxe-3fe683e ./

cd ipxe-3fe683e/src

echo '========= build IPXE =========='
sh build.sh

cd ../../

