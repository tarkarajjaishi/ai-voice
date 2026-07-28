#!/usr/bin/env bash
#
# Build and install the G.729 codec for Asterisk.
#
# WHY THIS IS NEEDED
#   Stock Asterisk ships format_g729.so and res_format_attr_g729.so, which handle
#   the FILE FORMAT and SDP ATTRIBUTES only — they let Asterisk pass G.729 through
#   untouched, but not transcode it. `core show translation` has no g729 row.
#   The AI pipeline needs signed-linear PCM, so on a G.729-only trunk (Ncell) the
#   agent hears nothing until this module exists.
#
#   Licensing: the core G.729 patents expired in 2017, and bcg729 is Belledonne's
#   LGPL implementation — no per-channel licence is required (unlike Sangoma's
#   codec_g729).
#
#   PREFER G711: if the carrier will enable alaw, take that instead. G.729 is
#   8 kbps CS-ACELP and is the worst possible input for Nepali ASR. This module
#   makes G.729 *work*; it does not make it *good*.
#
# Verified on: Ubuntu 26.04, Asterisk 22.5.2, 2026-07-28
#
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "── 1/5 dependencies ────────────────────────────────────────────────"
# libbcg729-dev is packaged, so only the Asterisk module wrapper is built here.
# asterisk-dev MUST match the running Asterisk version or the module won't load.
apt-get update -qq
apt-get install -y -qq asterisk-dev libbcg729-dev build-essential autoconf automake libtool git
test -f /usr/include/asterisk/frame.h || { echo "asterisk headers missing"; exit 1; }

echo "── 2/5 locating the module directory ───────────────────────────────"
MODDIR="$(asterisk -rx 'core show settings' 2>/dev/null | awk -F': *' '/Module directory/{print $2}' | xargs || true)"
[ -z "${MODDIR:-}" ] && MODDIR="$(dirname "$(find /usr/lib -name 'codec_ulaw.so' 2>/dev/null | head -1)")"
[ -d "$MODDIR" ] || { echo "could not locate Asterisk module dir"; exit 1; }
echo "    $MODDIR"

echo "── 3/5 fetching asterisk-g72x (supports Asterisk 1.4 – 22.x) ───────"
rm -rf /usr/src/asterisk-g72x
git clone --depth 1 -q https://github.com/arkadijs/asterisk-g72x.git /usr/src/asterisk-g72x
cd /usr/src/asterisk-g72x

echo "── 4/5 building ────────────────────────────────────────────────────"
./autogen.sh  > /tmp/g729-autogen.log   2>&1
./configure --with-bcg729 > /tmp/g729-configure.log 2>&1
make > /tmp/g729-make.log 2>&1
SO="$(find . -name 'codec_g729.so' | head -1)"
[ -n "$SO" ] || { echo "build produced no codec_g729.so — see /tmp/g729-make.log"; exit 1; }
install -m 644 "$SO" "$MODDIR/codec_g729.so"

echo "── 5/5 loading + verifying ─────────────────────────────────────────"
asterisk -rx "module load codec_g729.so" >/dev/null 2>&1 || true
sleep 2
if asterisk -rx "core show translation" 2>/dev/null | grep -qE "^\s*g729\s"; then
    echo "✅ g729 transcoding ACTIVE — a g729 row is present in the translation table"
    asterisk -rx "module show like codec_g729" | tail -2
else
    echo "❌ module installed but no g729 translation row — check 'asterisk -rx \"module show like g729\"'"
    exit 1
fi

echo
echo "It persists across restarts via autoload=yes in modules.conf."
echo "Re-run this after ANY Asterisk upgrade — the module is built against"
echo "the headers of one specific version and will refuse to load otherwise."
