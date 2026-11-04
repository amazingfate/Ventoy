#!/bin/bash
# Collect the LiveCD fallback fonts that Kiosk's DejaVu set does not cover.
#
# Only Regular is installed. The upstream zips also contain every other
# weight; those stay in the download cache. Font files are not stored in git.

set -eu

dest=${1:?usage: collect-fonts.sh DEST}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/build/versions.env"

rm -rf "$dest"
mkdir -p "$dest"

extract() {
    url=$1
    name=$2
    member=$3
    family=$4
    zip=$("$ROOT/build/download.sh" "$url" "$name")
    python3 - "$zip" "$member" "$dest" "$family" <<'PY'
import os
import struct
import sys
import zipfile

zip_path, member, dest, family = sys.argv[1:]
with zipfile.ZipFile(zip_path) as archive:
    data = archive.read(member)
out = os.path.join(dest, os.path.basename(member))
with open(out, "wb") as handle:
    handle.write(data)

count = struct.unpack(">H", data[4:6])[0]
offset = 12
name = None
for _ in range(count):
    tag, _checksum, table_off, table_len = struct.unpack(">4sIII", data[offset:offset + 16])
    offset += 16
    if tag == b"name":
        name = data[table_off:table_off + table_len]
        break
if name is None:
    raise SystemExit(f"{out} has no name table")

records, string_off = struct.unpack(">HH", name[2:6])
found = set()
cursor = 6
for _ in range(records):
    platform, _enc, _lang, name_id, length, name_off = struct.unpack(">HHHHHH", name[cursor:cursor + 12])
    cursor += 12
    if name_id not in (1, 16):
        continue
    raw = name[string_off + name_off:string_off + name_off + length]
    if platform == 3:
        text = raw.decode("utf-16-be", "replace")
    else:
        text = raw.decode("latin1", "replace")
    found.add(text)
if family not in found:
    raise SystemExit(f"{out} family is {sorted(found)}, expected {family}")
PY
}

extract "$NOTO_SC_URL" "18_NotoSansSC.zip" "NotoSansSC-Regular.otf" "Noto Sans SC"
extract "$NOTO_TC_URL" "19_NotoSansTC.zip" "NotoSansTC-Regular.otf" "Noto Sans TC"
extract "$NOTO_JP_URL" "16_NotoSansJP.zip" "NotoSansJP-Regular.otf" "Noto Sans JP"
extract "$NOTO_KR_URL" "17_NotoSansKR.zip" "NotoSansKR-Regular.otf" "Noto Sans KR"
extract "$NOTO_THAI_URL" "NotoSansThai-v${NOTO_THAI_VERSION}.zip" \
    "NotoSansThai/full/ttf/NotoSansThai-Regular.ttf" "Noto Sans Thai"
extract "$NOTO_DEVA_URL" "NotoSansDevanagari-v${NOTO_DEVA_VERSION}.zip" \
    "NotoSansDevanagari/full/ttf/NotoSansDevanagari-Regular.ttf" "Noto Sans Devanagari"
extract "$NOTO_BENG_URL" "NotoSansBengali-v${NOTO_BENG_VERSION}.zip" \
    "NotoSansBengali/full/ttf/NotoSansBengali-Regular.ttf" "Noto Sans Bengali"
extract "$NOTO_TAML_URL" "NotoSansTamil-v${NOTO_TAML_VERSION}.zip" \
    "NotoSansTamil/full/ttf/NotoSansTamil-Regular.ttf" "Noto Sans Tamil"
extract "$NOTO_MLYM_URL" "NotoSansMalayalam-v${NOTO_MLYM_VERSION}.zip" \
    "NotoSansMalayalam/full/ttf/NotoSansMalayalam-Regular.ttf" "Noto Sans Malayalam"

cp -a "$ROOT/LiveCDGUI/fonts/69-ventoy-noto.conf" "$dest/"

count=$(find "$dest" -type f \( -name '*.otf' -o -name '*.ttf' \) | wc -l)
if [ "$count" -ne 9 ]; then
    echo "expected 9 fonts in $dest, found $count" >&2
    exit 1
fi
echo "collected 9 Noto Regular fonts into $dest"
