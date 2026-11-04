#!/bin/bash
# Build the ntfsprogs that Porteus Kiosk 5.5 left out.
#
# Kiosk 5.5.0 tracks the Gentoo portage snapshot of 2023-03-18 (glibc 2.36)
# and includes ntfs3g 2022.10.3's FUSE driver only. Gentoo does not publish
# a binary package for it, so ntfsresize and ntfsfix are built from the
# upstream tarball that ebuild uses and linked statically. A static binary
# runs on the kiosk without using the build machine's glibc.

set -eu

dest=${1:?usage: collect-ntfs3g.sh DEST}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/build/versions.env"

tarball=$("$ROOT/build/download.sh" "$KIOSK_NTFS3G_URL" "ntfs-3g_ntfsprogs-${KIOSK_NTFS3G_VERSION}.tgz")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tar -xzf "$tarball" -C "$work"
src=$work/ntfs-3g_ntfsprogs-${KIOSK_NTFS3G_VERSION}
cd "$src"

if ! ./configure --disable-ntfs-3g --disable-crypto --enable-static --disable-shared >"$work/build.log" 2>&1; then
    cat "$work/build.log" >&2
    exit 1
fi
if ! make -C libntfs-3g >>"$work/build.log" 2>&1; then
    cat "$work/build.log" >&2
    exit 1
fi
if ! make -C ntfsprogs ntfsresize ntfsfix >>"$work/build.log" 2>&1; then
    cat "$work/build.log" >&2
    exit 1
fi

lib=$src/libntfs-3g/.libs/libntfs-3g.a
if [ ! -f "$lib" ]; then
    lib=$src/libntfs-3g/libntfs-3g.a
fi

rm -rf "$dest"
mkdir -p "$dest/bin" "$dest/sbin"
gcc -static -O2 -o "$dest/sbin/ntfsresize" ntfsprogs/ntfsresize.o ntfsprogs/utils.o "$lib"
gcc -static -O2 -o "$dest/bin/ntfsfix" ntfsprogs/ntfsfix.o ntfsprogs/utils.o "$lib"
strip "$dest/sbin/ntfsresize" "$dest/bin/ntfsfix"

for tool in "$dest/sbin/ntfsresize" "$dest/bin/ntfsfix"; do
    if ! file "$tool" | grep -q 'statically linked'; then
        echo "$tool is not statically linked" >&2
        exit 1
    fi
done

"$dest/sbin/ntfsresize" --help >/dev/null
"$dest/bin/ntfsfix" --help >/dev/null
echo "built static ntfsresize and ntfsfix ${KIOSK_NTFS3G_VERSION} into $dest"
