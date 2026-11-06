#!/bin/bash

if [ "$1" = "sim" ]; then
    exopt="-DVENTOY_SIM"
fi

build_func() {    
    libsuffix=$2
    toolDir=$3
    
    XXFLAG='-std=gnu99 -D_FILE_OFFSET_BITS=64 -O2'
    XXLIB=""
    
    echo "CC=$1 libsuffix=$libsuffix toolDir=$toolDir"    
    
    echo "CC civetweb.o"
    $1 $XXFLAG -c -Wall -Wextra -Wshadow -Wformat-security -Winit-self \
        -Wmissing-prototypes -DLINUX \
        -I./src/Lib/libhttp/include \
        -DNDEBUG -DNO_CGI -DNO_CACHING -DNO_SSL -DSQLITE_DISABLE_LFS -DSSL_ALREADY_INITIALIZED \
        -DUSE_STACK_SIZE=102400 -DNDEBUG -fPIC \
        ./src/Lib/libhttp/include/civetweb.c \
        -o ./civetweb.o

    echo "CC plugson.o"
    $1 $XXFLAG $exopt -Wall -Wno-unused-function -DSTATIC=static -DINIT= \
        -I./src \
        -I./src/Core \
        -I./src/Web \
        -I./src/Include \
        -I./src/Lib/libhttp/include \
        -I./src/Lib/fat_io_lib/include \
        -I./src/Lib/xz-embedded/linux/include \
        -I./src/Lib/xz-embedded/linux/include/linux \
        -I./src/Lib/xz-embedded/userspace \
        -I ./src/Lib/exfat/src/libexfat \
        -I ./src/Lib/exfat/src/mkfs \
        -I ./src/Lib/fat_io_lib \
        \
        -L ./src/Lib/fat_io_lib/lib \
        src/main_linux.c \
        src/Core/ventoy_crc32.c \
        src/Core/ventoy_disk.c \
        src/Core/ventoy_disk_linux.c \
        src/Core/ventoy_json.c \
        src/Core/ventoy_log.c \
        src/Core/ventoy_md5.c \
        src/Core/ventoy_utf.c \
        src/Core/ventoy_util.c \
        src/Core/ventoy_util_linux.c \
        src/Web/*.c \
        src/Lib/xz-embedded/linux/lib/decompress_unxz.c \
        src/Lib/fat_io_lib/*.c \
        $XXLIB \
        -l pthread \
        ./civetweb.o \
        -o Plugson$libsuffix

    rm -f *.o
    
    if [ "$libsuffix" = "aa64" ]; then
        aarch64-linux-gnu-strip Plugson$libsuffix
    elif [ "$libsuffix" = "m64e" ]; then
        if command -v mips64el-linux-gnuabi64-strip >/dev/null 2>&1; then
            mips64el-linux-gnuabi64-strip Plugson$libsuffix
        else
            mips-linux-gnu-strip Plugson$libsuffix
        fi
    elif [ "$libsuffix" = "32" ] && command -v i686-linux-gnu-strip >/dev/null 2>&1; then
        i686-linux-gnu-strip Plugson$libsuffix
    else
        strip Plugson$libsuffix
    fi
    
    rm -f ../INSTALL/tool/$toolDir/Plugson
    cp -a Plugson$libsuffix ../INSTALL/tool/$toolDir/Plugson
    
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

