# Golden Baseline — Full Local GPU (Kroko + Qwen 2.5 + Kokoro)

## Quick Reference

| Field | Value |
|---|---|
| **Provider** | `local` (full monolithic) |
| **STT** | Kroko embedded (ONNX, on-premise) |
| **LLM** | Qwen 2.5 3B Instruct Q4_K_M (GPU) |
| **TTS** | Kokoro (neural, voice=af_heart) |
| **Transport** | AudioSocket |
| **Downstream** | Streaming |
| **Config** | `config/ai-agent.golden-local-gpu.yaml` |
| **GPU Tested** | NVIDIA RTX 4090 (24 GB VRAM) |
| **Reference Call** | `1772323042.221` on 10.44.0.103 |

## Validated Behavior

- **Greeting**: Streamed via Kokoro TTS, ~2.3s latency from request to first audio chunk
- **Two-way audio**: Full duplex via AudioSocket, caller speech detected by local Enhanced VAD + WebRTC VAD
- **Barge-in**: `local_vad_fallback` triggered with criteria=4, energy=11173, conf=1.0 — robust
- **Response latency**: 1.7–3.5s (STT finalization + LLM inference + TTS start)
- **Tool calling**: `hangup_call` detected and executed via structured tool gateway
- **Hangup**: Tool-driven (`agent_hangup`), farewell TTS played before disconnect
- **Call duration**: 45 seconds, clean teardown

## Key Latencies (Reference Call)

| Event | Time from call start |
|---|---|
| Call start (Stasis) | T+0.0s |
| Greeting TTS request sent | T+0.07s |
| First greeting audio chunk | T+2.36s |
| First frame to speaker | T+2.39s |
| User transcript #1 | T+13.8s |
| Agent response #1 | T+17.2s (~3.5s response) |
| Barge-in triggered | T+32.4s |
| User transcript #2 | T+35.7s |
| Agent farewell + hangup_call | T+37.5s (~1.7s response) |
| Call hung up | T+45.2s |

## .env Requirements (local-ai-server)

```env
GPU_AVAILABLE=true
LOCAL_LLM_GPU_LAYERS=-1
LOCAL_LLM_MODEL_PATH=/app/models/llm/qwen2.5-3b-instruct-q4_k_m.gguf
LOCAL_LLM_MAX_TOKENS=48
LOCAL_LLM_TEMPERATURE=0.3
LOCAL_STT_BACKEND=kroko
KROKO_EMBEDDED=1
KROKO_MODEL_PATH=/app/models/kroko/Kroko-EN-Community-64-L-Streaming-001.data
KROKO_LANGUAGE=en-US
LOCAL_TTS_BACKEND=kokoro
KOKORO_MODEL_PATH=/app/models/tts/kokoro
KOKORO_MODE=local
KOKORO_VOICE=af_heart
INCLUDE_KOKORO=true
INCLUDE_KROKO_EMBEDDED=true
```

## VAD & Barge-In Notes

- `use_provider_vad: false` — local Enhanced VAD + WebRTC VAD active
- Local provider has **no server-side AEC**, so local VAD fallback is the primary barge-in mechanism
- Barge-in energy threshold: 1000 (higher than cloud baselines due to local TTS echo potential)
- `provider_fallback_providers` includes `local`

## Quick Validation Checklist

1. Place call to the local provider context
2. Verify greeting plays within ~3 seconds
3. Speak and confirm STT transcription in logs
4. Verify agent responds within ~4 seconds
5. Interrupt agent mid-response — barge-in should trigger
6. Say goodbye — agent should use `hangup_call` tool and disconnect

## Logs

Reference logs archived at:
`archived/logs/2026-02-28_local-gpu-golden_1772323042.221/`
