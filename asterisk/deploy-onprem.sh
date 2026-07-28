#!/usr/bin/env bash
#
# ═══════════════════════════════════════════════════════════════════════════════
# Digital Nepal AI Call — on-prem deployment
#
# Takes a fresh Ubuntu/Debian box to a working Ncell trunk + AI voice agent.
# Idempotent: safe to re-run. Every stage verifies itself and fails loudly.
#
#   sudo ./deploy-onprem.sh --check                     # verify only, change nothing
#   sudo ./deploy-onprem.sh \
#        --erp-url http://10.0.0.5:8009/api/ai/v1 \
#        --erp-token 'xxxx' \
#        --did 9801234567
#
# WHAT THIS SCRIPT WILL NOT DO
#   It will not configure VLAN 3030 for you. Reconfiguring networking over SSH is
#   how boxes get lost; it prints the netplan you need and stops instead. Ncell
#   authenticates by source IP, so this machine MUST hold 10.111.7.76 on VLAN 3030
#   or nothing else here matters.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Trunk facts, from Ncell's provisioning sheet (DGT86USV01) ─────────────────
OUR_IP=10.111.7.76
OUR_CIDR=10.111.7.72/29
NCELL_GW=10.111.7.73
NCELL_SIG=(116.68.210.56 116.68.213.56)
NCELL_RTP=(116.68.210.57 116.68.210.58 116.68.210.59)
VLAN_ID=3030
CHANNELS=15

ERP_URL="${ERP_URL:-http://127.0.0.1:8009/api/ai/v1}"
ERP_TOKEN="${ERP_TOKEN:-}"
NCELL_DID="${NCELL_DID:-}"
CHECK_ONLY=0
AVA_DIR=/root/Asterisk-AI-Voice-Agent
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --check)      CHECK_ONLY=1; shift ;;
    --erp-url)    ERP_URL="$2"; shift 2 ;;
    --erp-token)  ERP_TOKEN="$2"; shift 2 ;;
    --did)        NCELL_DID="$2"; shift 2 ;;
    -h|--help)    sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
stage(){ printf '\n\033[1m══ %s\033[0m\n' "$*"; }
die()  { bad "$*"; exit 1; }

# ═══ 0. Preflight ════════════════════════════════════════════════════════════
stage "0. Preflight"
[ "$(id -u)" -eq 0 ] || die "run as root"
[ "$(uname -m)" = "x86_64" ] || die "x86_64 required (AVA does not support ARM64)"
. /etc/os-release
case "$ID" in ubuntu|debian) ok "OS: $PRETTY_NAME" ;; *) die "Ubuntu/Debian required, found $ID" ;; esac
[ -d /run/systemd/system ] || die "systemd required"
ok "systemd present"

# The gate everything else depends on.
if ip -4 -o addr show | grep -q "$OUR_IP"; then
  ok "holds $OUR_IP"
else
  bad "this box does NOT hold $OUR_IP"
  cat <<EOF

  Ncell checks the SOURCE IP of our SIP requests, so the trunk cannot work until
  this interface exists. Identify the NIC facing the Ncell handoff, then add a
  VLAN $VLAN_ID subinterface. Example /etc/netplan/60-ncell.yaml:

    network:
      version: 2
      vlans:
        ncell$VLAN_ID:
          id: $VLAN_ID
          link: <PHYSICAL_NIC>        # e.g. eno1 — check with: ip -br link
          addresses: [$OUR_IP/29]

  Apply with:  netplan try     (auto-reverts if it breaks your connection)

  Re-run this script afterwards.
EOF
  exit 1
fi

if ping -c 2 -W 2 "$NCELL_GW" >/dev/null 2>&1; then
  ok "Ncell gateway $NCELL_GW responds to ping"
else
  warn "$NCELL_GW does not answer ping — many carriers block ICMP, continuing"
fi

[ -n "$ERP_TOKEN" ] || die "--erp-token is required (the bearer token for the ERP voice shim)"
if curl -fsS -m 10 -o /dev/null -H "Authorization: Bearer $ERP_TOKEN" "$ERP_URL/models"; then
  ok "ERP shim reachable at $ERP_URL"
else
  die "ERP shim NOT reachable at $ERP_URL — fix this first, the agent has no brain without it"
fi

[ -n "$NCELL_DID" ] || warn "no --did given; outbound caller ID will be unset (Ncell may reject calls)"

if [ "$CHECK_ONLY" = "1" ]; then
  stage "--check requested; stopping before any changes"
  exit 0
fi

# ═══ 1. Base packages + Asterisk ══════════════════════════════════════════════
stage "1. Asterisk + Docker"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq asterisk asterisk-dev docker.io docker-compose-v2 git curl openssl sox
systemctl enable --now asterisk docker >/dev/null 2>&1 || true
AST_VER="$(asterisk -V | grep -oE '[0-9]+' | head -1)"
[ "$AST_VER" -ge 18 ] || die "Asterisk 18+ required, found $(asterisk -V)"
ok "$(asterisk -V)"
ok "docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# ═══ 2. G.729 transcoding ═════════════════════════════════════════════════════
stage "2. G.729 codec"
# Stock Asterisk can only PASS G.729 through; the AI needs signed-linear PCM.
if asterisk -rx "core show translation" 2>/dev/null | grep -qE "^\s*g729\s"; then
  ok "g729 transcoding already active"
else
  [ -x "$HERE/build-codec-g729.sh" ] || die "build-codec-g729.sh not found next to this script"
  "$HERE/build-codec-g729.sh"
  asterisk -rx "core show translation" 2>/dev/null | grep -qE "^\s*g729\s" \
    || die "g729 still not transcodable after build"
  ok "g729 transcoding built and active"
fi

# ═══ 3. Asterisk configuration ════════════════════════════════════════════════
stage "3. Asterisk config (ARI + trunk + dialplan)"

# ARI rides on the HTTP server, which ships DISABLED. Loopback only: AVA's
# containers use network_mode host, so 127.0.0.1 inside them IS this box.
ARI_PASS_FILE=/etc/asterisk/.ava-ari-password
[ -f "$ARI_PASS_FILE" ] || { openssl rand -hex 16 > "$ARI_PASS_FILE"; chmod 600 "$ARI_PASS_FILE"; }
ARI_PASS="$(cat "$ARI_PASS_FILE")"

grep -qE '^\s*enabled\s*=\s*yes' /etc/asterisk/http.conf || cat >> /etc/asterisk/http.conf <<'EOF'

; --- Digital Nepal AI Call ---
[general](+)
enabled=yes
bindaddr=127.0.0.1
bindport=8088
EOF

grep -q '^\[ava\]' /etc/asterisk/ari.conf || cat >> /etc/asterisk/ari.conf <<EOF

; --- Digital Nepal AI Call ---
[ava]
type = user
read_only = no
password = $ARI_PASS
password_format = plain
EOF

for f in pjsip_ncell.conf extensions_ncell.conf extensions_ncell_outbound.conf; do
  [ -f "$HERE/$f" ] || die "$f missing next to this script"
  install -m 640 -o asterisk -g root "$HERE/$f" "/etc/asterisk/$f"
done
grep -q 'pjsip_ncell.conf'             /etc/asterisk/pjsip.conf      || printf '\n#include "pjsip_ncell.conf"\n' >> /etc/asterisk/pjsip.conf
grep -q 'extensions_ncell.conf'        /etc/asterisk/extensions.conf || printf '\n#include "extensions_ncell.conf"\n' >> /etc/asterisk/extensions.conf
grep -q 'extensions_ncell_outbound.conf' /etc/asterisk/extensions.conf || printf '#include "extensions_ncell_outbound.conf"\n' >> /etc/asterisk/extensions.conf

# Caller ID for outbound, read by the dialplan.
if [ -n "$NCELL_DID" ]; then
  grep -q '^NCELL_DID=' /etc/asterisk/globals_ncell.conf 2>/dev/null \
    || printf '[globals]\nNCELL_DID=%s\n' "$NCELL_DID" > /etc/asterisk/globals_ncell.conf
  chown asterisk:root /etc/asterisk/globals_ncell.conf; chmod 640 /etc/asterisk/globals_ncell.conf
  grep -q 'globals_ncell.conf' /etc/asterisk/extensions.conf || printf '#include "globals_ncell.conf"\n' >> /etc/asterisk/extensions.conf
fi

systemctl restart asterisk; sleep 6
asterisk -rx "pjsip show endpoint ncell-trunk" 2>&1 | grep -q "ncell-trunk" || die "trunk endpoint did not load"
ok "trunk endpoint loaded (cap: $CHANNELS channels)"
ok "ARI user 'ava' configured (password in $ARI_PASS_FILE)"

# ═══ 4. Firewall ══════════════════════════════════════════════════════════════
stage "4. Firewall"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  for ip in "$NCELL_GW" "${NCELL_SIG[@]}" "${NCELL_RTP[@]}"; do
    ufw allow from "$ip" to any port 5060 proto udp >/dev/null 2>&1 || true
    ufw allow from "$ip" to any port 10000:20000 proto udp >/dev/null 2>&1 || true
  done
  ok "ufw rules added for Ncell signalling + RTP"
else
  warn "ufw inactive — ensure UDP 5060 and 10000-20000 are open to Ncell's addresses"
fi

# ═══ 5. AVA (the voice agent) ═════════════════════════════════════════════════
stage "5. AVA"
if [ ! -d "$AVA_DIR" ]; then
  git clone --depth 1 https://github.com/hkjarral/Asterisk-AI-Voice-Agent.git "$AVA_DIR"
fi
cd "$AVA_DIR"
chmod +x preflight.sh
./preflight.sh --apply-fixes --force </dev/null >/tmp/ava-preflight.log 2>&1 || true
grep -qE "Checks passed|Warnings" /tmp/ava-preflight.log && ok "preflight done" || warn "check /tmp/ava-preflight.log"

set_kv() {
  local k="$1" v="$2"
  if grep -q "^${k}=" .env 2>/dev/null; then sed -i "s|^${k}=.*|${k}=${v}|" .env; else printf '%s=%s\n' "$k" "$v" >> .env; fi
}
set_kv ASTERISK_HOST 127.0.0.1
set_kv ASTERISK_ARI_PORT 8088
set_kv ASTERISK_ARI_USERNAME ava
set_kv ASTERISK_ARI_PASSWORD "$ARI_PASS"
# NOT Telnyx: security.py enforces env-only secrets for that provider family and
# pops any inline api_key, so the ERP shim token must live under this name.
set_kv TELNYX_API_KEY "$ERP_TOKEN"
set_kv LOCAL_STT_BACKEND faster_whisper
set_kv LOCAL_TTS_BACKEND piper
set_kv INCLUDE_FASTER_WHISPER true
set_kv INCLUDE_PIPER true
for m in VOSK SHERPA KOKORO LLAMA WHISPER_CPP MELOTTS SILERO; do set_kv "INCLUDE_$m" false; done
set_kv LOCAL_AI_MODE minimal

# Nepali TTS voice — AVA's own model_setup.sh has no Nepali entry.
mkdir -p models/tts models/stt
V=ne_NP-chitwan-medium
B=https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ne/ne_NP/chitwan/medium
for f in "$V.onnx" "$V.onnx.json"; do
  [ -s "models/tts/$f" ] || curl -fsSL -o "models/tts/$f" "$B/$f"
done
ok "Piper Nepali voice present"
set_kv LOCAL_TTS_MODEL_PATH "/app/models/tts/${V}.onnx"

[ -f "$HERE/../ava/config/ai-agent.erp-nepali.yaml.example" ] \
  && cp "$HERE/../ava/config/ai-agent.erp-nepali.yaml.example" config/ai-agent.local.yaml \
  || warn "pipeline example not found; write config/ai-agent.local.yaml manually"
sed -i "s|chat_base_url:.*|chat_base_url: ${ERP_URL}|g" config/ai-agent.local.yaml 2>/dev/null || true
chown 1000:1000 config/ai-agent.local.yaml 2>/dev/null || true

# COMPOSE_BAKE=false: compose declares network:host at BUILD time, which buildx
# refuses without --allow=network.host — and then exits 0 having built nothing.
COMPOSE_BAKE=false docker compose -p asterisk-ai-voice-agent up -d --build admin_ui ai_engine local_ai_server
ok "AVA containers started"

# ═══ 6. Verify ════════════════════════════════════════════════════════════════
stage "6. Verification"
sleep 45
curl -fsS -m 10 -u "ava:$ARI_PASS" http://127.0.0.1:8088/ari/asterisk/info >/dev/null \
  && ok "ARI responds" || bad "ARI not responding"
asterisk -rx "ari show apps" 2>&1 | grep -q "asterisk-ai-voice-agent" \
  && ok "Stasis app registered" || bad "Stasis app NOT registered — is ai_engine running?"
docker logs --tail 300 ai_engine 2>&1 | grep -q "Pipeline validation SUCCESS" \
  && ok "pipeline validated" || warn "pipeline not validated — docker logs ai_engine"

TRUNK="$(asterisk -rx "pjsip show aor ncell-trunk" 2>&1 | grep -oE 'Avail|Unavail' | head -1)"
if [ "$TRUNK" = "Avail" ]; then
  ok "NCELL TRUNK IS UP — the box can place and receive real calls"
else
  bad "trunk shows '$TRUNK'"
  cat <<EOF
  Ncell is not answering our OPTIONS keepalive. Check, in order:
    1. Is the VLAN $VLAN_ID handoff physically connected and up?   ip -br link
    2. Does Ncell have OUR address ($OUR_IP) whitelisted on their side?
    3. Has a DID ("SIP number") actually been assigned? Their sheet left it blank.
    4. Packet-level truth:  tcpdump -ni any host $NCELL_GW and port 5060
EOF
fi

stage "Done"
cat <<EOF
  Admin UI     http://$(hostname -I | awk '{print $1}'):3003   (restrict this port!)
  Test inbound call once Ncell assigns a DID.
  Test outbound:
      asterisk -rx "channel originate PJSIP/9865760285@ncell-trunk extension 100@from-ai-agent"

  Recordings land in /var/spool/asterisk/monitor — every call, both directions.
EOF
