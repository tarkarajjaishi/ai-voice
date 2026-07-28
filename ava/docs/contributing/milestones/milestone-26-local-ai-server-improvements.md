# Milestone 26: Local AI Server Improvements (GPU hardening + Whisper stability)

## Summary

Harden the fully-local `local_ai_server` path (STT/LLM/TTS over WebSocket) for GPU cloud testing (Vast.ai) with reliable model switching via Admin UI, Whisper STT stability on ExternalMedia, and safe/consistent LLM prompting (including large system prompts).

## Status: 🚧 In Progress

## Problem Statement

Testing the “Fully Local” provider on a rented GPU exposed a few reliability gaps:

- **Whisper STT loop / self-echo**: with ExternalMedia, the agent could re-enter capture too early and keep responding while TTS was still playing.
- **Local LLM prompt mismatch**: the AI engine’s configured context/system prompt wasn’t consistently applied to `local_ai_server`, leading to irrelevant responses.
- **LLM context overflow**: large system prompts could exceed `LOCAL_LLM_CONTEXT` (default `768`) and crash llama.cpp with `Requested tokens exceed context window`.
- **Cloud reality**: Vast container templates don’t provide `systemd`/Docker daemon; the “GA” compose stack requires a VM instance + working NVIDIA Container Toolkit.

## Solution

### 1) Whisper-only stability for continuous-stream transport

Make “segment gating re-arm” behavior apply to the Local provider only when the runtime STT backend is Whisper, to avoid regressions in Vosk/Sherpa/Kroko.

### 2) Prompt sync between AI engine and local_ai_server

At session start, push the AI engine’s system prompt to `local_ai_server` so local LLM inference matches the configured context.

### 3) LLM context hardening

- Default the local server’s context window to **2048** when `GPU_AVAILABLE=true` (unless overridden via `LOCAL_LLM_CONTEXT`).
- Add startup-only **auto context** tuning (GPU only): select a working `n_ctx` from a safe ladder, then cache it per model/GPU so subsequent restarts reuse it.
- Add server-side guards so **no prompt** can exceed `n_ctx`:
  - Truncate system prompt as a last resort when the configured context is too small.
  - Reduce `max_tokens` dynamically based on prompt size.

## Implementation Details

### Local AI Server

| File | Change |
|------|--------|
| `local_ai_server/config.py` | Default `llm_context` to `2048` when `GPU_AVAILABLE=true` unless `LOCAL_LLM_CONTEXT` is set |
| `local_ai_server/server.py` | Guard llama.cpp calls: reduce `max_tokens` to fit context, and prevent prompt > `n_ctx` |
| `local_ai_server/server.py` | Prompt builder hardening: if system prompt alone exceeds `n_ctx`, truncate it (last resort) |
| `local_ai_server/server.py` | Startup-only auto-tune `llm_context` on GPU and cache selection (skip on reload/switch) |
| `local_ai_server/server.py` | Emit `stt_backend` field in `stt_result` payloads for engine-side backend-aware logic |

### AI Engine / Local Provider

| File | Change |
|------|--------|
| `src/providers/local.py` | On session start, request `status` from `local_ai_server` and sync `llm_config.system_prompt` (deduped by digest) |
| `src/providers/local.py` | Track runtime STT backend from `stt_result.stt_backend` (`faster_whisper` / `whisper_cpp`) |
| `src/engine.py` | Re-arm segment gating for `local` provider **only when** runtime STT backend is Whisper |

### Admin UI

| File | Change |
|------|--------|
| `admin_ui/frontend/src/pages/System/ModelsPage.tsx` | Show LLM “Prompt fit” diagnostics (system prompt tokens, safe max tokens) and allow tuning `n_ctx` + `max_tokens` |
| `admin_ui/backend/api/local_ai.py` | Allow `/api/local-ai/switch` to apply `llm_context` + `llm_max_tokens` (best-effort hot switch, fallback recreate) |

### Tests

| File | Change |
|------|--------|
| `tests/test_local_ai_server_config.py` | Verify `LOCAL_LLM_CONTEXT` default behavior (GPU=2048, CPU=768, env override respected) |
| `tests/test_local_provider_audio_timing.py` | Coverage for Whisper-only gating + backend detection (added during this milestone) |

## Operational Notes (Vast.ai)

- **Container/Jupyter templates**: good for quick model/latency benchmarking, but typically **don’t** run Docker daemon (`preflight.sh` will fail).
- **VM templates**: required for the full compose stack and long-running services.
- **GPU Docker**: ensure NVIDIA Container Toolkit is configured so Compose can allocate `--gpus`.

### Audit-Driven Hardening (added post-audit)

These changes come from a deep audit of the Local AI Server experience, focused on reducing community setup failures.

| File | Change | Why | How to Test |
|------|--------|-----|-------------|
| `admin_ui/backend/api/local_ai.py` | Capabilities fallback checks `GPU_AVAILABLE` and `LOCAL_AI_MODE` before claiming LLM is available | CPU minimal mode doesn't preload LLM; old fallback misled the UI | `curl localhost:3003/api/local-ai/capabilities` on CPU-only — `llm.available` should be `false` |
| `admin_ui/backend/api/local_ai.py` | `_read_env_values()` strips surrounding quotes from values | `.env` values like `VAR="value"` were read with quotes included | Set `LOCAL_STT_BACKEND="vosk"` in `.env`, switch model via UI, verify no quote in logs |
| `admin_ui/backend/api/local_ai.py` | Remove dead `_verify_model_loaded()` function | Superseded by `_wait_for_status()` in switch flow; also tried `ws://local_ai_server:8765` which doesn't resolve in host networking | `grep -n _verify_model_loaded admin_ui/backend/api/local_ai.py` returns empty |
| `.env.example` | Comment out `LOCAL_LLM_GPU_LAYERS=0` default | Users copying `.env.example` got CPU-only LLM on GPU systems without realizing | `grep LOCAL_LLM_GPU_LAYERS .env.example` shows commented-out line with `-1` suggestion |
| `preflight.sh` | Warn when `GPU_AVAILABLE=true` but `LOCAL_LLM_GPU_LAYERS=0` | Catches the footgun during onboarding | Set `GPU_AVAILABLE=true` + `LOCAL_LLM_GPU_LAYERS=0` in `.env`, run `./preflight.sh --local-server`, see warning |
| `preflight.sh` | Skip `asterisk_media/` checks in `--local-server` mode | Standalone GPU server doesn't need Asterisk media directories | `./preflight.sh --local-server` shows "Skipping asterisk_media checks" |
| `preflight.sh` | `check_ports_local_server()` uses grep instead of sourcing `.env` | Sourcing `.env` can execute arbitrary code | Inspect function — no `source` call |
| `docker-compose.yml` | Reduce healthcheck `retries` from 180 to 30 | Old: 3-hour window. New: 30 min (still generous) | `docker compose config` shows `retries: 30` |
| `local_ai_server/Dockerfile` | Add `EXPOSE 8765` | Documents WS port for tools/inspection | `docker inspect <image>` shows exposed port |
| `local_ai_server/Dockerfile.gpu` | Add `EXPOSE 8765` | Same as above for GPU image | Same |
| `docs/COMMUNITY_TEST_MATRIX.md` | New: publishable community test matrix with submission template | Crowdsource what model combinations work best for fully local | File exists with backend reference table and results section |
| `.github/ISSUE_TEMPLATE/local-ai-test-result.md` | New: structured issue template for test result submissions | Makes contributing test results easy for community | New issue → "Local AI Test Result" template available |

### Tool-Call Reliability Hardening (LLM-agnostic local provider)

| File | Change | Why | How to Test |
|------|--------|-----|-------------|
| `local_ai_server/server.py` | Add startup LLM tool-capability probe (`strict`/`partial`/`none`) and expose metadata | Different local GGUF models vary widely in tool-call compliance | `docker logs local_ai_server` includes `LLM TOOL-CALL PROBE`; `GET /api/system/health` shows `models.llm.tool_capability` |
| `src/providers/local.py` | Add policy resolver (`auto|strict|compatible|off`) and compact tool prompt mode | Reduce spoken leakage of tool instructions and keep behavior model-agnostic | Set `LOCAL_TOOL_CALL_POLICY=auto` and compare `strict` vs `partial` model behavior |
| `src/providers/local.py` | Add Tier-2 hidden repair turn for malformed tool output | Recover tool calls like malformed `*hangup_call*`/broken wrappers without speaking markup | Trigger malformed tool text in logs; verify `Recovered malformed local LLM tool call via repair turn` |
| `src/tools/telephony/hangup_policy.py` | Add fuzzy end-call intent normalization (`hand up`/`and the call`) | STT artifacts were blocking valid hangup intents | Say “hand up the call”; verify hangup guardrail allows tool execution |
| `src/engine.py` | Use fuzzy end-call matcher for local and pipeline hangup guardrails | Keep guardrail conservative but tolerant to STT noise | Validate no premature hangups on normal queries; valid goodbye phrases still pass |
| `admin_ui/frontend/src/pages/System/ModelsPage.tsx` | Show active LLM tool capability + effective tool policy | Make local provider behavior explicit for operators | Models page displays `Tool capability` and `Tool policy` fields |
| `config/ai-agent.yaml`, `.env.example`, `config/ai-agent.example.yaml` | Add `LOCAL_TOOL_CALL_POLICY` wiring | Allow operator override when auto policy is not preferred | Set `LOCAL_TOOL_CALL_POLICY=strict|compatible|off` and restart |
| `local_ai_server/protocol_contract.py`, `local_ai_server/ws_protocol.py`, `local_ai_server/server.py` | Add `llm_tool_request` / `llm_tool_response` protocol and structured tool normalization path | Stabilize tool execution for full-local provider while preserving parser fallback | Confirm logs show `LLM TOOL GATEWAY` and parsed tool calls for full-local calls |
| `src/providers/local.py` | Full-local-only gateway routing (`tool_gateway_enabled`) with timeout fallback and modular bypass | Keep STT-only/TTS-only modular adapters unchanged while hardening full-local tool calls | Verify full-local emits `llm_tool_request`; modular local adapters do not |
| `admin_ui/frontend/src/pages/Advanced/LLMPage.tsx` | Add Local Tool Calling panel with capability + resolved policy + override controls | Give operators visibility/control in LLM Defaults | Confirm page shows capability/resolved policy and persists `providers.local.tool_call_policy` |
| `local_ai_server/status_builder.py` | Expose `structured_mode`, `validated_at`, `model_fingerprint` via status | Make capability detection traceable and debuggable per model/runtime | Check `/api/system/health` local LLM status includes these fields |

## Verification Checklist

- `local_ai_server` starts on GPU with `LOCAL_LLM_GPU_LAYERS=-1` and `LOCAL_LLM_CONTEXT` unset → `llm_context=2048`.
- `local_ai_server` auto-tunes `llm_context` on first boot (GPU) and reports source (`auto`/`cache`) in status.
- Switching to Whisper STT (Faster-Whisper or whisper.cpp) no longer causes continuous self-talk on ExternalMedia.
- Switching between STT/TTS/LLM models via Admin UI succeeds for shipped backends; failures are capability-aware and actionable.
- No `Requested tokens exceed context window` errors in `local_ai_server` logs when using the default `default` context prompt.
- ✅ Capabilities endpoint returns `llm.available=false` on CPU-only systems (unless `LOCAL_AI_MODE=full`).
- ✅ `preflight.sh --local-server` skips asterisk_media and warns about GPU layers footgun.
- ✅ Community test matrix published at `docs/COMMUNITY_TEST_MATRIX.md`.
