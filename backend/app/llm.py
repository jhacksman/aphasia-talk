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
You are a communication assistant for a person with aphasia (difficulty producing language). Your job is to generate clear, natural sentences that express what they might be trying to say.

Rules:
- Generate 6-8 sentences per word, ranging from simple needs to more expressive/emotional thoughts
- Sentences should be first-person ("I..." or "Can you..." or "Please...")
- Mix practical sentences ("I need water") with deeper/emotional ones ("I miss how things used to be")
- Keep sentences short (under 15 words) — they will be spoken aloud by TTS
- If the user has bookmarked sentences for this word, those preferences indicate their style and needs — generate similar sentences
- Also suggest 4-6 related words that they might want to tap next
- Never generate anything condescending, childish, or patronizing — the user is an adult with full comprehension, they just can't produce the words themselves
- Output valid JSON only: {"sentences": [...], "related_words": [...]}"""


def _build_user_prompt(
    word: str,
    category: str | None,
    bookmarked: list[str],
    history: list[str],
    recent_question: str | None = None,
) -> str:
    parts = [f'The word the user tapped is: "{word}".']
    if category:
        parts.append(f"It is from the category: {category}.")
    if bookmarked:
        joined = "; ".join(f'"{b}"' for b in bookmarked)
        parts.append(f"Sentences they have previously saved for this word: {joined}.")
    if history:
        parts.append(f"Recent words they tapped: {', '.join(history)}.")
    if recent_question:
        parts.append(
            f'A moment ago someone asked them: "{recent_question}". If the word '
            "relates to the question, some sentences should work as replies to it."
        )
    parts.append('Generate JSON: {"sentences": [...strings...], "related_words": [...strings...]}.')
    return " ".join(parts)


# Gate for wake-word capture (ASK_MODE_PROPOSAL.md): only speech directed AT
# the user may reach their screen. Constant so vLLM prefix-caches it.
GATE_SYSTEM_PROMPT = """\
You screen speech captured near a person with aphasia (they understand language fully but cannot produce it). Decide whether the transcript is a question or request spoken directly TO them — something in the second person that they might want to answer, like "Are you hungry?" or "Do you want to sit outside?".

Not directed at them: speech ABOUT them in the third person ("she seemed tired", "he's already eaten"), television or radio dialogue, conversation between other people, fragments, or noise. A bare greeting or attention-getter with nothing to answer ("hey there", "good morning") is also false — there must be an actual question or request.

When uncertain, answer false — a missed question costs a repeat; a wrong one confuses the user.
Output JSON only: {"directed": true or false}"""


async def is_directed_at_user(text: str) -> bool:
    """True if the transcript is a question/request addressed directly to
    the user. Used to gate wake-word captures; failures gate closed (False)."""
    if settings.mock_inference:
        return text.rstrip().endswith("?")

    body = {
        "model": settings.vllm_model,
        "messages": [
            {"role": "system", "content": GATE_SYSTEM_PROMPT},
            {"role": "user", "content": f'Transcript: "{text}" /no_think'},
        ],
        "temperature": 0.0,
        "max_tokens": 16,
        "response_format": {"type": "json_object"},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    resp = await _get_client().post(
        f"{settings.vllm_url}/v1/chat/completions", json=body
    )
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"] or ""
    try:
        return bool(_extract_json(content).get("directed") is True)
    except (json.JSONDecodeError, ValueError, TypeError):
        return False


def _build_reply_prompt(question: str, context_turns: list[dict]) -> str:
    parts = []
    # Turns before the question itself, chronological, so the model sees the
    # exchange the way the room heard it.
    prior = [t for t in context_turns if t["text"] != question]
    if prior:
        lines = "; ".join(
            ("The user was asked" if t["role"] == "heard" else "The user said")
            + f': "{t["text"]}"'
            for t in prior
        )
        parts.append(f"Recent conversation: {lines}.")
    parts.append(f'Someone just asked the user: "{question}".')
    parts.append(
        "Generate candidate REPLIES the user might want to give. The replies "
        "must span the possible answers: include at least one affirmative, one "
        "negative, one uncertain or deferring, and one that redirects to what "
        "they might actually want. Never assume which answer is true for them. "
        "Related words should be words they might tap to steer their reply."
    )
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
    # Models sometimes repeat a related word; each should appear once.
    seen: set[str] = set()
    related = [w for w in related if not (w.lower() in seen or seen.add(w.lower()))]
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


async def _chat_sentences(
    user_prompt: str, system_prompt: str
) -> tuple[list[str], list[str]]:
    """One text chat call to vLLM, coerced to (sentences, related_words)."""
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
        # Qwen3.6 ignores the legacy /no_think soft switch; without this the
        # model burns max_tokens on reasoning_content and returns content=None.
        "chat_template_kwargs": {"enable_thinking": False},
    }
    resp = await _get_client().post(
        f"{settings.vllm_url}/v1/chat/completions", json=body
    )
    resp.raise_for_status()
    # content is None when the model spent the whole budget thinking.
    content = resp.json()["choices"][0]["message"]["content"] or ""

    try:
        sentences, related = _coerce_payload(_extract_json(content))
    except (json.JSONDecodeError, ValueError, TypeError):
        # Truncated (max_tokens) or non-JSON output: degrade to empty rather
        # than 500, so the client can show a "tap again" state.
        return [], []
    return sentences[: settings.max_sentences], related[:6]


async def generate_sentences(
    word: str,
    category: str | None,
    bookmarked: list[str],
    history: list[str],
    system_prompt: str = BASE_SYSTEM_PROMPT,
    recent_question: str | None = None,
) -> tuple[list[str], list[str]]:
    if settings.mock_inference:
        return _mock_generate(word, category, bookmarked)

    user_prompt = _build_user_prompt(
        word, category, bookmarked, history, recent_question
    )
    return await _chat_sentences(user_prompt, system_prompt)


async def generate_replies(
    question: str,
    context_turns: list[dict],
    system_prompt: str = BASE_SYSTEM_PROMPT,
) -> tuple[list[str], list[str]]:
    """Candidate replies to a question someone asked the user (Ask mode)."""
    if settings.mock_inference:
        return _mock_replies()

    return await _chat_sentences(
        _build_reply_prompt(question, context_turns), system_prompt
    )


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
                    {"type": "text", "text": "What is the main object, and what might the user want to say about it? /no_think"},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            },
        ],
        "temperature": 0.7,
        "max_tokens": 700,
        "response_format": {"type": "json_object"},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    resp = await _get_client().post(f"{settings.vllm_url}/v1/chat/completions", json=body)
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"] or ""

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


def _mock_replies() -> tuple[list[str], list[str]]:
    # Deterministic reply spread mirroring the real prompt's requirement:
    # affirmative / negative / deferral / redirect / emotional.
    return (
        [
            "Yes, please.",
            "No, thank you.",
            "Maybe a little later.",
            "I am not sure. Can you help me decide?",
            "I would rather do something else.",
            "That sounds nice.",
        ],
        ["yes", "no", "later", "help", "rest", "water"],
    )


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
