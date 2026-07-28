# ai-voice

AI voice agent for the Digital Nepal ERP — inbound and outbound calls in Nepali and English,
answered from the ERP's own knowledge base and recorded back into it.

## Status

| Piece | State |
|---|---|
| AVA (Asterisk voice agent) running locally | ✅ Admin UI on `:3003` |
| Django voice shim (`/api/ai/v1/…`) | ✅ live, 7/7 tests passing |
| Asterisk + ARI | ⬜ not installed yet |
| Ncell SIP trunk | ⬜ provisioned, not connected |
| Nepali→English structured extractor | ⬜ not started |
| Scheduled callbacks | ⬜ not started |

## Layout

- **`ava/`** — vendored copy of [hkjarral/Asterisk-AI-Voice-Agent][ava] (MIT). See *Attribution* below.

## Architecture

```
Ncell SIP trunk (G729, VLAN 3030, 15 channels)
  └─ Asterisk 18+  (bcg729 transcode, ARI)
       └─ AVA      (STT → LLM → TTS pipeline)
            ├─ STT: TBD — gated on the Nepali code-switching test
            ├─ LLM: → the ERP's own agent, via the voice shim   ← the integration seam
            └─ TTS: TBD
```

AVA is the **audio transducer**, not the brain. The brain is the ERP's existing agent
(`erp-backend/ai/agent.py`) with its tools, moderation, escalation and per-tenant audit trail.
AVA reaches it through an OpenAI-compatible shim, configured as a `type: telnyx` provider:

```yaml
providers:
  erp_llm:
    enabled: true
    type: telnyx                 # generic OpenAI-compatible chat-completions adapter
    capabilities: [llm]
    chat_base_url: "http://<erp-host>:8009/api/ai/v1"
    api_key: "${DN_VOICE_TOKEN}"
    chat_model: "erp/agent"      # the slash matters — see the shim's docstring
```

## Local development

AVA requires **Linux with systemd** and uses `network_mode: host`, so on Windows it runs in WSL2
with Docker installed *natively inside the distro* (not Docker Desktop integration).

```bash
sudo ./preflight.sh --apply-fixes --force
COMPOSE_BAKE=false docker compose -p asterisk-ai-voice-agent up -d --build admin_ui
```

Two gotchas worth knowing:

- **`--force` is required** if your distro is newer than AVA's supported list.
- **`COMPOSE_BAKE=false` is required.** Compose declares `network: host` at build time, which
  buildx refuses without `--allow=network.host`. Without it, `docker compose up --build`
  **exits 0 having built nothing** — the only tell is an empty `docker ps`.

## Known constraints

- **G729 only** on the Ncell trunk — the worst codec for ASR, and it stacks badly on code-switched
  Nepali. Ask Ncell for G711/PCMA; it is a config change on their side and the single biggest
  available accuracy win.
- **15 channels** — a hard concurrency ceiling. Outbound campaigns must never starve inbound.
- **Private peering** (`10.111.7.76`, VLAN 3030) — no cloud host can reach the trunk, so the
  Asterisk box must be on-prem.
- **Dates spoken by callers are Bikram Sambat.** Storing one as AD puts it ~57 years out.

## Attribution

`ava/` is a vendored copy of **[Asterisk-AI-Voice-Agent][ava]** by hkjarral, used under the
**MIT License**. The upstream licence is retained at [`ava/LICENSE`](ava/LICENSE). All credit for
that code belongs to its authors; it is vendored here only so this repository builds standalone.

[ava]: https://github.com/hkjarral/Asterisk-AI-Voice-Agent
