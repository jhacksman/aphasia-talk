"""Unit tests for the real-mode (non-mock) LLM parsing path.

A fake httpx client feeds canned vLLM responses so we can test the
resilience guards without a GPU or network.
"""
import asyncio

from app import llm
from app.config import settings


class _FakeResp:
    def __init__(self, content):
        self._content = content

    def raise_for_status(self):
        pass

    def json(self):
        return {"choices": [{"message": {"content": self._content}}]}


class _FakeClient:
    def __init__(self, content):
        self._content = content

    async def post(self, url, json=None):
        return _FakeResp(self._content)


def _use_real_with(monkeypatch, content):
    monkeypatch.setattr(settings, "mock_inference", False)
    monkeypatch.setattr(llm, "_client", _FakeClient(content))


def test_generate_parses_valid_json(monkeypatch):
    _use_real_with(monkeypatch, '{"sentences": ["I am thirsty."], "related_words": ["drink"]}')
    sents, related = asyncio.run(llm.generate_sentences("water", "Needs", [], []))
    assert sents == ["I am thirsty."]
    assert related == ["drink"]


def test_generate_degrades_on_non_json(monkeypatch):
    _use_real_with(monkeypatch, "Sorry, I cannot help with that.")
    assert asyncio.run(llm.generate_sentences("water", "Needs", [], [])) == ([], [])


def test_generate_degrades_on_truncated_json(monkeypatch):
    # Simulates hitting max_tokens mid-object.
    _use_real_with(monkeypatch, '{"sentences": ["I am thirsty.", "Can I have')
    assert asyncio.run(llm.generate_sentences("water", "Needs", [], [])) == ([], [])


def test_generate_handles_fenced_json(monkeypatch):
    _use_real_with(monkeypatch, '```json\n{"sentences": ["Hi."], "related_words": []}\n```')
    sents, related = asyncio.run(llm.generate_sentences("hi", None, [], []))
    assert sents == ["Hi."]


def test_vision_tolerates_qualitative_confidence(monkeypatch):
    _use_real_with(
        monkeypatch,
        '{"identified_object": "cup", "confidence": "high", '
        '"sentences": ["I want a drink."], "related_words": ["water"]}',
    )
    obj, conf, sents, related = asyncio.run(llm.generate_from_image(b"x", "image/jpeg"))
    assert obj == "cup"
    assert conf == 0.8  # non-numeric confidence falls back, no crash
    assert sents == ["I want a drink."]


def test_vision_degrades_on_garbage(monkeypatch):
    _use_real_with(monkeypatch, "no json here")
    assert asyncio.run(llm.generate_from_image(b"x", "image/jpeg")) == ("this", 0.0, [], [])


def test_replies_parse_and_degrade(monkeypatch):
    _use_real_with(monkeypatch, '{"sentences": ["Yes, please."], "related_words": ["yes"]}')
    sents, related = asyncio.run(llm.generate_replies("Are you hungry?", []))
    assert sents == ["Yes, please."]
    assert related == ["yes"]
    _use_real_with(monkeypatch, "not json")
    assert asyncio.run(llm.generate_replies("Are you hungry?", [])) == ([], [])


def test_user_prompt_includes_recent_question():
    p = llm._build_user_prompt("water", None, [], [], recent_question="Are you hungry?")
    assert 'asked her: "Are you hungry?"' in p
    assert "asked her" not in llm._build_user_prompt("water", None, [], [])


def test_reply_prompt_has_context_and_answer_spread():
    turns = [
        {"role": "heard", "text": "Did you sleep well?"},
        {"role": "spoken", "text": "Yes, I slept well."},
        {"role": "heard", "text": "Are you hungry?"},  # the question itself
    ]
    p = llm._build_reply_prompt("Are you hungry?", turns)
    assert 'She was asked: "Did you sleep well?"' in p
    assert 'She said: "Yes, I slept well."' in p
    # The question appears once as the ask, not duplicated into the context.
    assert p.count("Are you hungry?") == 1
    assert "Never assume which answer is true" in p


def test_transcript_hallucination_filter():
    from app import whisper

    assert whisper.clean_transcript(" Thanks for watching! ") == ""
    assert whisper.clean_transcript("you") == ""
    assert whisper.clean_transcript("Are you hungry?") == "Are you hungry?"
    # A real sentence containing a hallucination phrase is untouched.
    assert whisper.clean_transcript("Say thank you to Susan.") == "Say thank you to Susan."
