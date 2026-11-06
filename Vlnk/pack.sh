#!/bin/sh

cd "$(dirname "$0")"

cp -a ./VentoyVlnk.sh ../INSTALL/VentoyVlnk.sh

exe=./vs/VentoyVlnk/Release/VentoyVlnk.exe
if [ -f "$exe" ]; then
    cp -a "$exe" ../INSTALL/VentoyVlnk.exe
else
    echo "VentoyVlnk.exe is not built. Open Vlnk/vs/VentoyVlnk/VentoyVlnk.sln on Windows."
fi
