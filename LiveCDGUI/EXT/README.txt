
Files below are from Porteus-Kiosk-5.5.0-x86_64.iso
https://archive.org/download/porteus-kiosk-client/Porteus-Kiosk-5.5.0-x86_64.iso
MD5 d26752caac5f6124006b78a47dc70ecd

MD5SUM:
e2edc857acff4fd01f7ff557731debf9  EXT/000-kernel.xzm
65bed901c77890f80534c56bf12472bf  EXT/001-core.xzm
040eb93ce8ac24ecd03949523756457f  EXT/003-settings.xzm
63864f6c6cf3c3b62362a2e6bce58a3f  EXT/004-wifi.xzm
228f2e5e607a034941b6ce1f5be83429  EXT/initrd.xz
ca068f460d8f4d8e270e44eb0de07e36  EXT/vmlinuz


Porteus Kiosk 5.5.0 follows the Gentoo portage snapshot tagged 20230318 (glibc 2.36-r5). Its 001-core.xzm already contains ntfs3g 2022.10.3's FUSE driver (libntfs-3g.so.89) and does not contain ntfsresize or ntfsfix. initrd.sh runs collect-ntfs3g.sh, which downloads the upstream tarball used by the Gentoo ebuild for that version (https://download.tuxera.com/opensource/ntfs-3g_ntfsprogs-2022.10.3.tgz) and builds static ntfsresize and ntfsfix. DejaVu fonts are already in 001-core.xzm. The separate 06-fonts.xzm used with Kiosk 5.2 is not part of this ISO, and the old public URL for it now returns 404.

busybox-x86_64 is from https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64
MD5SUM
ea7e2353af0067a926d3e021e504290e  EXT/busybox-x86_64
