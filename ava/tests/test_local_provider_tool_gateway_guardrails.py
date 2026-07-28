from __future__ import annotations

import pytest

from src.config import LocalProviderConfig
from src.providers.local import LocalProvider


def test_transfer_intent_detector():
    assert LocalProvider._looks_like_transfer_intent("Can you transfer me to support?")
    assert LocalProvider._looks_like_transfer_intent("Please connect me to extension 7000")
    assert not LocalProvider._looks_like_transfer_intent("How much GPU memory does this need?")
    assert not LocalProvider._looks_like_transfer_intent("What is the setup process?")


def test_extract_hangup_farewell_from_tool_call():
    tool_calls = [
        {"name": "hangup_call", "parameters": {"farewell_message": "It was a pleasure assisting you. Goodbye!"}}
    ]
    assert (
        LocalProvider._extract_hangup_farewell(tool_calls)
        == "It was a pleasure assisting you. Goodbye!"
    )


def test_extract_hangup_farewell_strips_tool_chatter():
    tool_calls = [
        {"name": "hangup_call", "parameters": {"farewell_message": "Goodbye! (hangup_call tool executed)"}}
    ]
    assert LocalProvider._extract_hangup_farewell(tool_calls) == "Goodbye!"


@pytest.mark.asyncio
async def test_emit_local_llm_result_uses_hangup_farewell_and_drops_transfer():
    events = []

    async def on_event(event):
        events.append(event)

    provider = LocalProvider(LocalProviderConfig(), on_event)
    provider._allowed_tools = {"hangup_call", "live_agent_transfer"}
    provider._last_user_transcript_by_call["call-1"] = "That's all, thank you."

    await provider._emit_local_llm_result(
        call_id="call-1",
        llm_text=(
            "It was a pleasure assisting you. Goodbye! "
            "Hangup call successful. Call duration: 1 minute and 23 seconds."
        ),
        clean_text=(
            "It was a pleasure assisting you. Goodbye! "
            "Hangup call successful. Call duration: 1 minute and 23 seconds."
        ),
        tool_calls=[
            {"name": "live_agent_transfer", "parameters": {"target": "support"}},
            {"name": "hangup_call", "parameters": {"farewell_message": "It was a pleasure assisting you. Goodbye!"}},
        ],
        tool_path="structured",
    )

    transcript_event = next(event for event in events if event.get("type") == "agent_transcript")
    assert transcript_event["text"] == "It was a pleasure assisting you. Goodbye!"

    tool_event = next(event for event in events if event.get("type") == "ToolCall")
    assert [call["name"] for call in tool_event["tool_calls"]] == ["hangup_call"]


@pytest.mark.asyncio
async def test_emit_local_llm_result_uses_clean_goodbye_when_hangup_has_no_farewell():
    events = []

    async def on_event(event):
        events.append(event)

    provider = LocalProvider(LocalProviderConfig(), on_event)
    provider._allowed_tools = {"hangup_call"}
    provider._last_user_transcript_by_call["call-2"] = "Thank you. Goodbye."

    await provider._emit_local_llm_result(
        call_id="call-2",
        llm_text="Goodbye! (hangup_call tool executed)",
        clean_text="Goodbye! (hangup_call tool executed)",
        tool_calls=[{"name": "hangup_call", "parameters": {}}],
        tool_path="repair",
    )

    transcript_event = next(event for event in events if event.get("type") == "agent_transcript")
    assert transcript_event["text"] == "Goodbye!"
