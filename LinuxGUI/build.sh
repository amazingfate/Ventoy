#!/bin/bash

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
XZDIR=$("$ROOT/build/prepare-xz-embedded.sh")

build_func() {    
    libsuffix=$2
    toolDir=$3
    
    XXFLAG='-std=gnu99 -D_FILE_OFFSET_BITS=64'
    XXLIB=""
    
    echo "CC=$1 libsuffix=$libsuffix toolDir=$toolDir"    
    
    $1 $XXFLAG -c -Wall -Wextra -Wshadow -Wformat-security -Winit-self \
        -Wmissing-prototypes -O2 -DLINUX \
        -I./Ventoy2Disk/Lib/libhttp/include \
        -DNDEBUG -DNO_CGI -DNO_CACHING -DNO_SSL -DSQLITE_DISABLE_LFS -DSSL_ALREADY_INITIALIZED \
        -DUSE_STACK_SIZE=102400 -DNDEBUG -fPIC \
        ./Ventoy2Disk/Lib/libhttp/include/civetweb.c \
        -o ./civetweb.o || return 1
    
    $1 $XXFLAG -O2 -Wall -Wno-unused-function -DSTATIC=static -DINIT= \
        -I./Ventoy2Disk \
        -I./Ventoy2Disk/Core \
        -I./Ventoy2Disk/Web \
        -I./Ventoy2Disk/Include \
        -I./Ventoy2Disk/Lib/libhttp/include \
        -I./Ventoy2Disk/Lib/fat_io_lib/include \
        -I"$XZDIR/linux/include" \
        -I"$XZDIR/linux/include/linux" \
        -I"$XZDIR/userspace" \
        -I ./Ventoy2Disk/Lib/exfat/src/libexfat \
        -I ./Ventoy2Disk/Lib/exfat/src/mkfs \
        -I ./Ventoy2Disk/Lib/fat_io_lib \
        \
        -L ./Ventoy2Disk/Lib/fat_io_lib/lib \
        Ventoy2Disk/main_webui.c \
        Ventoy2Disk/Core/*.c \
        Ventoy2Disk/Web/*.c \
        "$XZDIR/linux/lib/decompress_unxz.c" \
        Ventoy2Disk/Lib/exfat/src/libexfat/*.c \
        Ventoy2Disk/Lib/exfat/src/mkfs/*.c \
        Ventoy2Disk/Lib/fat_io_lib/*.c \
        $XXLIB \
        -l pthread \
        ./civetweb.o \
        -o V2D$libsuffix || return 1

    rm -f *.o
    
    if [ "$libsuffix" = "aa64" ]; then
        aarch64-linux-gnu-strip V2D$libsuffix
    elif [ "$libsuffix" = "m64e" ]; then
        if command -v mips64el-linux-gnuabi64-strip >/dev/null 2>&1; then
            mips64el-linux-gnuabi64-strip V2D$libsuffix
        else
            mips-linux-gnu-strip V2D$libsuffix
        fi
    elif [ "$libsuffix" = "32" ] && command -v i686-linux-gnu-strip >/dev/null 2>&1; then
        i686-linux-gnu-strip V2D$libsuffix
    else
        strip V2D$libsuffix
    fi
    
    rm -f ../INSTALL/tool/$toolDir/V2DServer
    cp -a V2D$libsuffix ../INSTALL/tool/$toolDir/V2DServer
}

if echo 'int main(void){return 0;}' | gcc -m32 -x c -o /tmp/vt-m32 - >/dev/null 2>&1; then
    cc32="gcc -m32"
else
    cc32="i686-linux-gnu-gcc"
fi
rm -f /tmp/vt-m32

if command -v mips64el-linux-gnuabi64-gcc >/dev/null 2>&1; then
    ccmips="mips64el-linux-gnuabi64-gcc -mips64r2 -mabi=64"
elif command -v mips-linux-gnu-gcc >/dev/null 2>&1; then
    ccmips="mips-linux-gnu-gcc -mips64r2 -mabi=64"
else
    echo "no mips64el compiler" >&2
    exit 1
fi

build_func "gcc" '64' 'x86_64' || exit 1
build_func "$cc32" '32' 'i386' || exit 1
build_func "aarch64-linux-gnu-gcc" 'aa64' 'aarch64' || exit 1
build_func "$ccmips" 'm64e' 'mips64el' || exit 1


