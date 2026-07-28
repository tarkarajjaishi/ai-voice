# Deepgram — Golden Baseline

Use these references for a known-good Deepgram flow:

- Deepgram Agent Golden Baseline: `docs/case-studies/Deepgram-Agent-Golden-Baseline.md`

Quick checks to match the baseline:
- AudioSocket upstream active; downstream streaming with automatic file fallback
- No underflows; drift ~0%; correct μ-law/PCM alignment by design
- Latency P95 ≲ 2s; clear, natural audio
