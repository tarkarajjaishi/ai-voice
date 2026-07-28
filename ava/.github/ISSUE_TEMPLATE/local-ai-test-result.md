---
name: Local AI Test Result
about: Share your Local AI Server test results to help the community
title: "[Test Result] "
labels: ["community-test", "local-ai"]
assignees: ''
---

## Test Configuration

**Date**: <!-- YYYY-MM-DD -->
**Hardware**: <!-- e.g., "Ryzen 7 5800X, 32GB RAM" or "Vast.ai RTX 4090 24GB" -->
**OS**: <!-- e.g., "Ubuntu 22.04", "Debian 12" -->
**GPU**: <!-- e.g., "RTX 4090 24GB" or "None (CPU only)" -->
**Docker version**: <!-- docker --version -->

## Model Configuration

**STT Backend**: <!-- vosk / sherpa / kroko / faster_whisper / whisper_cpp -->
**STT Model**: <!-- e.g., "vosk-model-en-us-0.22" or "faster_whisper base" -->

**TTS Backend**: <!-- piper / kokoro / melotts -->
**TTS Voice/Model**: <!-- e.g., "en_US-lessac-medium" or "kokoro af_heart" -->

**LLM Model**: <!-- e.g., "phi-3-mini-4k-instruct.Q4_K_M.gguf" or "Cloud (GPT-4o)" -->
**LLM Context**: <!-- e.g., 2048 -->
**LLM GPU Layers**: <!-- e.g., -1 (auto), 0 (CPU), 35 -->

## Deployment

**Pipeline**: <!-- local_only / local_hybrid -->
**Transport**: <!-- ExternalMedia RTP / AudioSocket -->
**Deployment mode**: <!-- Single-host / Split-host (describe) -->
**Docker Compose**: <!-- docker-compose.yml only / with docker-compose.gpu.yml -->

## Results

**End-to-End Latency**: <!-- Approximate: e.g., "~2s", "3-5s" -->
**STT Latency**: <!-- If measured separately -->
**LLM Latency**: <!-- If measured separately -->
**TTS Latency**: <!-- If measured separately -->

**Call Quality (1-5)**:
<!-- 1=unusable, 2=poor, 3=usable, 4=good, 5=cloud-quality -->

**Number of test calls**: <!-- How many calls did you make? -->

## Observations

<!-- Any notable observations: echo issues, model switching, stability, etc. -->

## Logs (optional)

<details>
<summary>Relevant log snippets</summary>

```
<!-- Paste relevant logs here (redact any API keys/tokens) -->
```

</details>
