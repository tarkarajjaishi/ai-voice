# ElevenLabs Conversational AI Provider Implementation & API Reference

Complete technical reference for ElevenLabs Conversational AI integration in Asterisk AI Voice Agent.

## Overview

**File**: `src/providers/elevenlabs_agent.py`

ElevenLabs Conversational AI is a full-agent provider with built-in STT (Speech-to-Text), LLM reasoning, and TTS (Text-to-Speech) in a single WebSocket connection.

**Key Characteristics**:
- Single WebSocket endpoint for bidirectional audio + control
- Agent configuration managed via ElevenLabs web dashboard
- Client-side tool execution (tools defined in dashboard, executed locally)
- High-quality voice synthesis with multiple voice options
- Supports PCM16 @ 16kHz audio format

---

## Setup Guide

### Step 1: Create ElevenLabs Agent

1. Go to [ElevenLabs Agents](https://elevenlabs.io/app/agents)
2. Click **"Create Agent"**
3. Configure your agent:
   - **Name**: Your agent name (e.g., "Customer Support Agent")
   - **Voice**: Select a voice from the library
   - **First Message**: Initial greeting (e.g., "Hello! How can I help you today?")
   - **System Prompt**: Define agent behavior and personality
   - **LLM Model**: Select model (GPT-4o, Claude, etc.)

### Step 2: Enable Agent Security (Required)

**CRITICAL**: You must enable authentication for your agent.

1. In your agent settings, go to **"Security"** tab
2. Enable **"Require authentication"**
3. This generates a signed URL for secure connections

Without authentication, the agent cannot be accessed via API.

### Step 3: Get Agent ID

1. In your agent dashboard, look at the URL or agent details
2. Copy the **Agent ID** (format: `agent_xxxxxxxxxxxxxxxxxxxxxxxxxxxx`)
3. Add to your `.env` file:
   ```env
   ELEVENLABS_API_KEY=your_api_key_here
   ELEVENLABS_AGENT_ID=agent_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

### Step 4: Add Client Tools

ElevenLabs uses **Client Tools** - tools defined in the dashboard but executed by your application.

1. In agent settings, go to **"Tools"** tab
2. Click **"Add Tool"** → **"Client Tool"**
3. Paste the JSON schema for each tool (see [Tool Schemas](#tool-schemas) below)
4. **Link tools to agent**: Ensure tools show "Dependent agents" includes your agent

---

## Configuration

### YAML Configuration

```yaml
providers:
  elevenlabs_agent:
    api_key: ${ELEVENLABS_API_KEY}
    agent_id: ${ELEVENLABS_AGENT_ID}
    enabled: true
    
    # Audio Configuration
    input_sample_rate: 16000
    output_sample_rate: 16000
    input_encoding: pcm16
    output_encoding: pcm16

contexts:
  demo_elevenlabs:
    provider: elevenlabs_agent
    greeting: ""  # Greeting managed by ElevenLabs agent
```

### Environment Variables

```env
ELEVENLABS_API_KEY=xi-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ELEVENLABS_AGENT_ID=agent_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Tool Schemas

### hangup_call

Ends the call gracefully after a farewell message.

```json
{
  "name": "hangup_call",
  "description": "Use this tool when the caller wants to end the call, says goodbye, or there's nothing more to discuss. Always use a polite farewell message.",
  "parameters": {
    "type": "object",
    "properties": {
      "farewell_message": {
        "type": "string",
        "description": "A polite goodbye message to say before hanging up"
      }
    },
    "required": []
  }
}
```

### transfer

Transfers the call to another destination.

```json
{
  "name": "transfer",
  "description": "Transfer the call to another person, department, or extension. Use when caller requests to speak with someone specific or needs specialized help.",
  "parameters": {
    "type": "object",
    "properties": {
      "destination": {
        "type": "string",
        "description": "The transfer destination - can be 'sales_agent', 'support_agent', 'sales_queue', 'support_queue', 'sales_team', or 'support_team'"
      }
    },
    "required": ["destination"]
  }
}
```

> **Note**: The tool registry also accepts `transfer_call` as an alias for backwards compatibility.

### cancel_transfer

Cancels an in-progress transfer.

```json
{
  "name": "cancel_transfer",
  "description": "Cancel an ongoing call transfer and return to speaking with the caller directly.",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

### leave_voicemail

Initiates voicemail recording.

```json
{
  "name": "leave_voicemail",
  "description": "Allow the caller to leave a voicemail message when the requested person is unavailable.",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

### send_email_summary

Sends an email summary of the conversation.

```json
{
  "name": "send_email_summary",
  "description": "Send a summary of this conversation to an email address.",
  "parameters": {
    "type": "object",
    "properties": {
      "recipient_email": {
        "type": "string",
        "description": "Email address to send the summary to"
      },
      "notes": {
        "type": "string",
        "description": "Additional notes to include in the email"
      }
    },
    "required": []
  }
}
```

### request_transcript

Sends the full conversation transcript to the caller.

```json
{
  "name": "request_transcript",
  "description": "Send the full conversation transcript to the caller's email address.",
  "parameters": {
    "type": "object",
    "properties": {
      "caller_email": {
        "type": "string",
        "description": "The caller's email address to send the transcript to"
      }
    },
    "required": ["caller_email"]
  }
}
```

---

## WebSocket API

### Connection Flow

1. **Get Signed URL**: Request authenticated URL from ElevenLabs API
2. **Connect**: Open WebSocket to signed URL
3. **Receive** `conversation_initiation_metadata`: Session started
4. **Stream** audio chunks (PCM16 base64 @ 16kHz)
5. **Receive** agent audio, transcripts, and tool calls
6. **Send** tool results back to agent
7. **Respond** to ping messages with pong

### Signed URL Endpoint

```http
POST https://api.elevenlabs.io/v1/convai/conversation/get_signed_url
Headers:
  xi-api-key: YOUR_API_KEY
Body:
  {"agent_id": "agent_xxxx"}
```

Response:
```json
{
  "signed_url": "wss://api.elevenlabs.io/v1/convai/conversation?..."
}
```

### WebSocket Endpoint (via Signed URL)

```
wss://api.elevenlabs.io/v1/convai/conversation?agent_id={agent_id}&...
```

---

## Server-to-Client Messages

### `conversation_initiation_metadata`

Session started successfully.

```json
{
  "type": "conversation_initiation_metadata",
  "conversation_id": "conv_xxxx",
  "agent_output_audio_format": "pcm_16000"
}
```

### `audio`

Agent audio chunk (base64-encoded PCM16).

```json
{
  "type": "audio",
  "audio": "base64_encoded_pcm16_data"
}
```

### `user_transcript`

User speech transcript.

```json
{
  "type": "user_transcript",
  "user_transcript": "Hello, I need help with my order"
}
```

### `agent_response`

Agent text response.

```json
{
  "type": "agent_response",
  "agent_response": "I'd be happy to help you with your order!"
}
```

### `client_tool_call`

Tool execution request.

```json
{
  "type": "client_tool_call",
  "tool_call_id": "hangup_call_abc123",
  "tool_name": "hangup_call",
  "parameters": {
    "farewell_message": "Goodbye!"
  }
}
```

**CRITICAL**: Must respond with `client_tool_result` promptly.

### `interruption`

Barge-in detected - user started speaking during agent speech.

```json
{
  "type": "interruption"
}
```

### `ping`

Keep-alive message.

```json
{
  "type": "ping",
  "ping_event": {"event_id": 123}
}
```

Must respond with `pong`.

---

## Client-to-Server Messages

### `audio` (User Audio)

Send user audio as base64-encoded PCM16.

```json
{
  "type": "audio",
  "audio": "base64_encoded_pcm16_data"
}
```

### `client_tool_result`

Tool execution result.

```json
{
  "type": "client_tool_result",
  "tool_call_id": "hangup_call_abc123",
  "result": "{\"status\": \"success\", \"will_hangup\": true}",
  "is_error": false
}
```

### `pong`

Response to ping keep-alive.

```json
{
  "type": "pong",
  "pong_event": {"event_id": 123}
}
```

---

## Audio Formats

### Input: PCM16 @ 16kHz

```python
audio_config = {
    "input_sample_rate": 16000,
    "input_encoding": "pcm16"
}
```

### Output: PCM16 @ 16kHz

ElevenLabs outputs PCM16 audio at 16kHz sample rate.

### Audio Pipeline

```
Asterisk AudioSocket (μ-law 8kHz)
    ↓
ai_engine: Convert to PCM16 16kHz
    ↓
Send to ElevenLabs (base64 PCM16)
    ↓
ElevenLabs processes
    ↓
Receive PCM16 16kHz
    ↓
ai_engine: Resample to 8kHz, convert to μ-law
    ↓
Asterisk AudioSocket
```

---

## Tool Execution Flow

### Event Handling

```
ElevenLabs → client_tool_call
    ↓
Provider emits function_call event
    ↓
Engine._execute_provider_tool()
    ↓
tool_registry.get(function_name)
    ↓
tool.execute(parameters, context)
    ↓
Provider.send_tool_result()
    ↓
ElevenLabs receives client_tool_result
```

### Hangup Tool Special Handling

For `hangup_call` tool, the engine schedules a delayed hangup:

```python
if function_name == "hangup_call" and result.get("will_hangup"):
    # Schedule hangup after 3 seconds to let farewell play
    async def delayed_hangup():
        await asyncio.sleep(3.0)
        await ari_client.hangup_channel(channel_id)
    
    asyncio.create_task(delayed_hangup())
```

---

## Conversation History

Transcripts are captured from provider events:

- `transcript` event → User speech → `{"role": "user", "content": "..."}`
- `agent_transcript` event → Agent speech → `{"role": "assistant", "content": "..."}`

History is stored in `session.conversation_history` for email summaries and transcript requests.

---

## Common Issues & Fixes

### Issue: Tools Not Linked to Agent

**Symptoms**:
- Tools created but agent doesn't use them
- "No dependent agents" shown in tool settings

**Fix**: In ElevenLabs dashboard, edit each tool and ensure your agent is selected under "Dependent agents".

### Issue: "Quota Exceeded" Error

**Symptoms**:
- WebSocket closes with "This request exceeds your quota limit"
- Connection fails after initial success

**Cause**: ElevenLabs account has hit usage limits.

**Fix**: Check your ElevenLabs dashboard for quota status, upgrade plan if needed.

### Issue: Audio Sent But No Response

**Symptoms**:
- `send_audio skipped: ws=True, connected=False`
- No agent response after user speaks

**Cause**: WebSocket not fully connected when audio sent.

**Fix**: Ensure `_connected` flag is True before sending audio. Provider handles this internally.

### Issue: Empty Email Transcripts

**Symptoms**:
- Email summary/transcript sent but conversation is empty

**Cause**: Conversation history not captured from provider events.

**Fix**: Ensure `transcript` and `agent_transcript` events are handled in `on_provider_event`.

### Issue: Call Doesn't Hang Up

**Symptoms**:
- `hangup_call` tool executes successfully but call continues

**Cause**: ElevenLabs manages its own TTS, so `cleanup_after_tts` doesn't work.

**Fix**: Use delayed hangup (3 second delay) instead of waiting for `AgentAudioDone`.

---

## Production Validation

### Golden Baseline

**Validated**: December 2, 2025  
**Call ID**: 1764710654.6786  
**Status**: ✅ Production Ready

**Performance Metrics**:
- Connection: Signed URL authentication ✅
- Audio Quality: Clear bidirectional ✅
- Tool Execution: hangup_call tested ✅
- Conversation History: Captured ✅
- Email Summary: Sent successfully ✅

**Log Excerpts**:
```
[info] 🔧 Function call received from provider function_name=hangup_call
[info] 📞 Hangup requested farewell=Is there anything else I can help with? Goodbye!
[info] ✅ Tool execution complete status=success
[info] Hangup requested - scheduling delayed hangup
[info] Email summary sent successfully
```

---

## References

### ElevenLabs Documentation
- Conversational AI: https://elevenlabs.io/docs/conversational-ai/overview
- WebSocket API: https://elevenlabs.io/docs/conversational-ai/api-reference
- Client Tools: https://elevenlabs.io/docs/conversational-ai/customization/tools
- Authentication: https://elevenlabs.io/docs/api-reference/authentication

### Project Documentation
- Provider Implementation: `src/providers/elevenlabs_agent.py`
- Config Classes: `src/providers/elevenlabs_config.py`
- Tool Adapter: `src/tools/adapters/elevenlabs.py`

---

## Architecture Notes

### Full Agent vs Pipeline

ElevenLabs is a **full agent provider** (like Deepgram, OpenAI Realtime):
- Single WebSocket handles STT + LLM + TTS
- Agent configuration managed externally (ElevenLabs dashboard)
- No separate pipeline components needed

### Client Tools Model

Unlike Deepgram which sends function schemas in the Settings message, ElevenLabs uses a **client tools** model:
- Tools are defined in the ElevenLabs web dashboard
- Agent decides when to call tools based on conversation
- Our system receives `client_tool_call` events and executes locally
- Results sent back via `client_tool_result`

This separation means:
- Tool schemas must match between dashboard and our implementation
- Tool logic lives in our codebase (`src/tools/`)
- ElevenLabs only knows tool names and parameters, not implementation
