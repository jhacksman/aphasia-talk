"""Sentence + related-word generation.

Talks to a vLLM OpenAI-compatible endpoint when available, and falls back to
a deterministic mock so the API is fully exercisable without a GPU.
"""
from __future__ import annotations

import json
import re

import httpx

from .config import settings

# Reused across requests so the connection to vLLM stays warm (keep-alive),
# rather than paying TCP/TLS setup on every /generate call. Created lazily so
# importing this module has no side effects.
_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=settings.request_timeout)
    return _client


async def aclose() -> None:
    global _client
    if _client is not None:
        try:
            await _client.aclose()
        finally:
            # Always drop the reference — otherwise a failed close leaves a
            # dead client that every future request would reuse.
            _client = None

# Base system prompt. The profile layer (app/profile.py) appends a persona
# section to this; the composed result is constant per deployment (one user),
# so vLLM still prefix-caches it and TTFT stays ~0.12s. Keep it byte-stable.
BASE_SYSTEM_PROMPT = """\
You are a communication assistant for a person with aphasia (difficulty producing language) caused by Alzheimer's disease. Your job is to generate clear, natural sentences that express what she might be trying to say.

Rules:
- Generate 6-8 sentences per word, ranging from simple needs to more expressive/emotional thoughts
- Sentences should be first-person ("I..." or "Can you..." or "Please...")
- Mix practical sentences ("I need water") with deeper/emotional ones ("I miss how things used to be")
- Keep sentences short (under 15 words) — they will be spoken aloud by TTS
- If the user has bookmarked sentences for this word, those preferences indicate her style and needs — generate similar sentences
- Also suggest 4-6 related words that she might want to tap next
- Never generate anything condescending, childish, or patronizing — she is an adult with full comprehension, she just can't produce the words herself
- Output valid JSON only: {"sentences": [...], "related_words": [...]}"""


def _build_user_prompt(
    word: str,
    category: str | None,
    bookmarked: list[str],
    history: list[str],
) -> str:
    parts = [f'The word she tapped is: "{word}".']
    if category:
        parts.append(f"It is from the category: {category}.")
    if bookmarked:
        joined = "; ".join(f'"{b}"' for b in bookmarked)
        parts.append(f"Sentences she has previously saved for this word: {joined}.")
    if history:
        parts.append(f"Recent words she tapped: {', '.join(history)}.")
    parts.append('Generate JSON: {"sentences": [...strings...], "related_words": [...strings...]}.')
    return " ".join(parts)


def _coerce_payload(raw: dict) -> tuple[list[str], list[str]]:
    """Pull sentences + related words out of a model response, tolerating
    either bare strings or {"text": ...} objects in the sentences list."""
    sentences: list[str] = []
    for s in raw.get("sentences", []):
        if isinstance(s, str):
            sentences.append(s.strip())
        elif isinstance(s, dict) and s.get("text"):
            sentences.append(str(s["text"]).strip())
    related = [str(w).strip() for w in raw.get("related_words", []) if str(w).strip()]
    return [s for s in sentences if s], related


def _extract_json(text: str) -> dict:
    """Find the first JSON object in a model response. /no_think output is
    usually clean JSON, but be defensive about stray prose or code fences."""
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        text = fence.group(1)
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        text = text[start : end + 1]
    return json.loads(text)


async def generate_sentences(
    word: str,
    category: str | None,
    bookmarked: list[str],
    history: list[str],
    system_prompt: str = BASE_SYSTEM_PROMPT,
) -> tuple[list[str], list[str]]:
    if settings.mock_inference:
        return _mock_generate(word, category, bookmarked)

    user_prompt = _build_user_prompt(word, category, bookmarked, history)
    body = {
        "model": settings.vllm_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            # /no_think keeps Qwen3.6 in fast non-reasoning mode for low latency.
            {"role": "user", "content": user_prompt + " /no_think"},
        ],
        "temperature": 0.7,
        "max_tokens": 600,
        "response_format": {"type": "json_object"},
    }
    resp = await _get_client().post(
        f"{settings.vllm_url}/v1/chat/completions", json=body
    )
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"]

    try:
        sentences, related = _coerce_payload(_extract_json(content))
    except (json.JSONDecodeError, ValueError, TypeError):
        # Truncated (max_tokens) or non-JSON output: degrade to empty rather
        # than 500, so the client can show a "tap again" state.
        return [], []
    return sentences[: settings.max_sentences], related[:6]


async def generate_from_image(
    image_bytes: bytes, mime: str, system_prompt: str = BASE_SYSTEM_PROMPT
) -> tuple[str, float, list[str], list[str]]:
    """Identify an object in a photo, then generate sentences about it."""
    if settings.mock_inference:
        obj = "cup"
        sents, related = _mock_generate(obj, None, [])
        return obj, 0.9, sents, related

    import base64

    data_url = f"data:{mime};base64,{base64.b64encode(image_bytes).decode()}"
    body = {
        "model": settings.vllm_model,
        "messages": [
            {
                "role": "system",
                "content": system_prompt
                + '\nFirst identify the single main object in the image. Output JSON: '
                + '{"identified_object": str, "confidence": float, "sentences": [...], "related_words": [...]}',
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "What is the main object, and what might she want to say about it? /no_think"},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            },
        ],
        "temperature": 0.7,
        "max_tokens": 700,
        "response_format": {"type": "json_object"},
    }
    resp = await _get_client().post(f"{settings.vllm_url}/v1/chat/completions", json=body)
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"]

    try:
        raw = _extract_json(content)
        sentences, related = _coerce_payload(raw)
        obj = str(raw.get("identified_object", "this")).strip() or "this"
        try:
            confidence = float(raw.get("confidence", 0.8))
        except (ValueError, TypeError):
            # Vision models often report qualitative confidence ("high").
            confidence = 0.8
    except (json.JSONDecodeError, ValueError, TypeError):
        return "this", 0.0, [], []
    return obj, confidence, sentences[: settings.max_sentences], related[:6]


# ── Mock generator ────────────────────────────────────────────────────────

_PRACTICAL = {
    "water": ["I am thirsty.", "Can I have some water please?", "I need something to drink.", "My throat is dry."],
    "food": ["I am hungry.", "Can I have something to eat?", "I would like a small meal.", "Is it time to eat?"],
    "bathroom": ["I need the bathroom.", "Please help me to the bathroom.", "I need to go now.", "Can you take me?"],
    "medicine": ["I need my medicine.", "Is it time for my pills?", "Please bring my medication.", "Did I take it already?"],
    "rest": ["I need to rest.", "I am very tired.", "I would like to lie down.", "Can I sleep for a while?"],
    "help": ["I need help right now.", "Please help me.", "Can someone come?", "Something is wrong."],
    "pain": ["I am in pain.", "It hurts here.", "Please help, it hurts.", "I need something for the pain."],
}

_EMOTIONAL = {
    "happy": ["I feel content right now.", "This makes me glad.", "I am happy you are here."],
    "sad": ["I feel sad today.", "I miss how things used to be.", "I just need a moment."],
    "love": ["I love you.", "You mean everything to me.", "I am grateful for you."],
    "scared": ["I feel frightened.", "Please stay with me.", "I don't want to be alone."],
    "family": ["Please call my family.", "I want to see my family.", "Tell them I love them."],
    "confused": ["I feel confused.", "Can you explain it again?", "I am not sure where I am."],
    "frustrated": ["I feel frustrated.", "This is hard for me.", "Please be patient with me."],
    "hello": ["Hello, it's good to see you.", "Hi there.", "I'm glad you're here."],
    "goodbye": ["Goodbye for now.", "I'll miss you.", "See you soon."],
    "thank you": ["Thank you so much.", "I really appreciate that.", "You are very kind."],
    "sorry": ["I'm sorry.", "I didn't mean to.", "Please forgive me."],
    "please": ["Please help me.", "If you could, please.", "I would really appreciate it."],
    "okay": ["Okay, that's fine.", "I understand.", "That works for me."],
}

_RELATED = {
    "water": ["drink", "juice", "cold", "ice", "cup", "thirsty"],
    "food": ["eat", "hungry", "snack", "meal", "fruit", "soup"],
    "bathroom": ["help", "now", "wash", "toilet", "clean", "private"],
    "medicine": ["pain", "doctor", "pills", "time", "water", "nurse"],
    "rest": ["bed", "tired", "sleep", "quiet", "blanket", "lie down"],
    "help": ["now", "please", "call", "family", "nurse", "pain"],
    "pain": ["medicine", "doctor", "help", "hurt", "head", "back"],
    "family": ["call", "visit", "love", "phone", "home", "miss"],
    "love": ["family", "hug", "thank you", "happy", "you", "together"],
    "hello": ["goodbye", "friend", "family", "happy", "you", "come"],
    "goodbye": ["hello", "love", "later", "miss", "family", "soon"],
    "thank you": ["please", "happy", "love", "help", "kind", "good"],
    "sorry": ["please", "help", "confused", "sad", "okay", "understand"],
    "please": ["help", "thank you", "water", "need", "now", "want"],
    "okay": ["yes", "no", "good", "understand", "fine", "thank you"],
}


def _mock_generate(word: str, category: str | None, bookmarked: list[str]) -> tuple[list[str], list[str]]:
    w = word.lower().strip()
    sentences: list[str] = []
    # Bookmarked sentences are the user's curated favorites — surface first.
    sentences.extend(bookmarked)
    sentences.extend(_PRACTICAL.get(w, []))
    sentences.extend(_EMOTIONAL.get(w, []))
    if not _PRACTICAL.get(w) and not _EMOTIONAL.get(w):
        sentences.extend(
            [
                f"I want to talk about {word}.",
                f"Can we do something with {word}?",
                f"I am thinking about {word}.",
                f"Please help me with {word}.",
            ]
        )
    # De-duplicate while preserving order.
    seen: set[str] = set()
    deduped = [s for s in sentences if not (s in seen or seen.add(s))]
    related = _RELATED.get(w, ["help", "yes", "no", "more", "please", "thank you"])
    return deduped[: settings.max_sentences], related[:6]
