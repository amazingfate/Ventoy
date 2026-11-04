#!/bin/sh
# Build Ventoy's UEFI applications from a current EDK2 stable tag.
# The applications stay in this repo. This script copies them into a
# source checkout and appends a [Components] section, instead of keeping
# a second copy of edk2-stable201911.
#
# Usage: build/build-edk2.sh [X64|IA32|AARCH64|LOONGARCH64]...

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/build/versions.env"

SRC="$ROOT/.cache/edk2"
APP_SRC="$ROOT/EDK2/edk2_mod/edk2-edk2-stable201911/MdeModulePkg/Application"
OUT="$ROOT/build/out/edk2"

if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$EDK2_TAG" "$EDK2_URL" "$SRC"
fi
git -C "$SRC" submodule update --init --depth 1 \
    MdePkg/Library/MipiSysTLib/mipisyst \
    MdeModulePkg/Library/BrotliCustomDecompressLib/brotli \
    BaseTools/Source/C/BrotliCompress/brotli \
    CryptoPkg/Library/OpensslLib/openssl \
    UnitTestFrameworkPkg/Library/CmockaLib/cmocka \
    MdeModulePkg/Universal/RegularExpressionDxe/oniguruma \
    RedfishPkg/Library/JsonLib/jansson || true

cp -a "$APP_SRC/Ventoy" "$APP_SRC/VtoyUtil" "$APP_SRC/VtoyShim" "$APP_SRC/VDiskChain" \
    "$SRC/MdeModulePkg/Application/"

DSC="$SRC/MdeModulePkg/MdeModulePkg.dsc"
if ! grep -q 'Application/Ventoy/Ventoy.inf' "$DSC"; then
    cat >> "$DSC" << 'EOF'

[Components]
  MdeModulePkg/Application/Ventoy/Ventoy.inf
  MdeModulePkg/Application/VtoyUtil/VtoyUtil.inf
  MdeModulePkg/Application/VtoyShim/VtoyShim.inf
  MdeModulePkg/Application/VDiskChain/VDiskChain.inf
EOF
fi

export PACKAGES_PATH="$SRC"
export EDK_TOOLS_PATH="$SRC/BaseTools"
export WORKSPACE="$SRC"
make -C "$SRC/BaseTools" -j"$(nproc)"
# edksetup.sh reads the caller's positional parameters. Hide the arch list.
setup_edk() {
    set --
    set +u
    cd "$SRC"
    # shellcheck disable=SC1091
    . ./edksetup.sh
    cd "$ROOT"
    set -u
}
requested="$*"
setup_edk

if [ -z "$requested" ]; then
    set -- X64
    command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 && set -- "$@" AARCH64
    command -v loongarch64-linux-gnu-gcc >/dev/null 2>&1 && set -- "$@" LOONGARCH64
else
    # shellcheck disable=SC2086
    set -- $requested
fi

mkdir -p "$OUT"
for arch in "$@"; do
    case "$arch" in
        X64) prefix="" ;;
        IA32) prefix="" ;;
        AARCH64) export GCC_AARCH64_PREFIX=aarch64-linux-gnu- ;;
        LOONGARCH64) export GCC_LOONGARCH64_PREFIX=loongarch64-linux-gnu- ;;
        *) echo "unknown arch $arch" >&2; exit 1 ;;
    esac
    # Current EDK2 accepts only one -m per invocation.
    # fbx64 follows the x64 Rocky shim layout. LoongArch boots the GRUB image directly.
    modules="Ventoy VtoyUtil"
    if [ "$arch" != "LOONGARCH64" ]; then
        modules="$modules VtoyShim VDiskChain"
    fi
    for mod in $modules; do
        build -p MdeModulePkg/MdeModulePkg.dsc -a "$arch" -b RELEASE -t GCC \
            -m "MdeModulePkg/Application/$mod/$mod.inf"
    done
    mkdir -p "$OUT/$arch"
    find "$SRC/Build/MdeModule/RELEASE_GCC/$arch" -name '*.efi' -path '*/OUTPUT/*.efi' \
        -exec cp -a {} "$OUT/$arch/" \;
done

find "$OUT" -name '*.efi' -printf '%p %s\n' | sort
