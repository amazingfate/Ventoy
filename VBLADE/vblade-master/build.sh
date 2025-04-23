#!/bin/bash

rm -f vblade_64 vblade_32 vblade_aa64

gcc linux.c aoe.c ata.c bpf.c -Os -o vblade_64
gcc linux.c aoe.c ata.c bpf.c -Os -m32 -o vblade_32
aarch64-buildroot-linux-uclibc-gcc linux.c aoe.c ata.c bpf.c -Os -static -o vblade_aa64

if [ -e vblade_64 ] && [ -e vblade_32 ] && [ -e vblade_aa64 ] && [ -e vblade_la64 ]; then
    echo -e '\n################## SUCCESS ######################\n'
else
    echo -e '\n################## FAILED ######################\n'
    exit 1
fi

