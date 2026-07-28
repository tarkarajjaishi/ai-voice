# ElevenLabs Agent Golden Baseline

**Status**: ✅ Production Ready  
**Provider**: `elevenlabs_agent` (full agent)

## Overview

This document is the **golden baseline** for the ElevenLabs Conversational AI provider.
It is intended as a known-good reference configuration for validating call behavior, audio quality, and tool execution.

## Requirements

- `ELEVENLABS_API_KEY` set in `.env`
- `ELEVENLABS_AGENT_ID` set in `.env`
- Asterisk 18+ with ARI enabled
- Docker + Docker Compose v2

## Golden Configuration (reference)

### Provider (YAML)

Use the `elevenlabs_agent` provider with telephony-friendly input/output settings:

```yaml
providers:
  elevenlabs_agent:
    enabled: true
    type: full
    capabilities: [stt, llm, tts]
    input_encoding: ulaw
    input_sample_rate_hz: 8000
    provider_input_encoding: pcm16
    provider_input_sample_rate_hz: 16000
    output_encoding: pcm16
    output_sample_rate_hz: 16000
    target_encoding: ulaw
    target_sample_rate_hz: 8000
```

### Context (YAML)

```yaml
contexts:
  demo_elevenlabs:
    provider: elevenlabs_agent
    profile: telephony_ulaw_8k
    tools:
      - transfer
      - cancel_transfer
      - hangup_call
      - leave_voicemail
      - send_email_summary
      - request_transcript
```

### Dialplan (Asterisk)

```ini
[from-ai-agent]
exten => s,1,NoOp(AI Voice Agent - ElevenLabs)
 same => n,Set(AI_CONTEXT=demo_elevenlabs)
 same => n,Set(AI_PROVIDER=elevenlabs_agent)
 same => n,Stasis(asterisk-ai-voice-agent)
 same => n,Hangup()
```

## Validation Checklist

- Clean call start and initial greeting
- No audio stutter/underflow during normal conversation
- Tool calls execute (at least `hangup_call`, and one of `transfer` or `request_transcript`)
- Clean hangup (no “dead air” at the end)

## Related Docs

- Provider setup: `docs/Provider-ElevenLabs-Setup.md`
- Provider implementation reference: `docs/contributing/references/Provider-ElevenLabs-Implementation.md`
- Golden YAML configs: `config/ai-agent.golden-elevenlabs.yaml`

