"""Linguistic profile / persona layer.

The language a person has most deeply imprinted — and, in Alzheimer's, the
language best preserved and most recognizable to her as her own — comes from
her formative years (roughly ages 10-30; the "reminiscence bump"). We bias
generation toward that voice using a profile keyed by birth era and region,
optionally refined by an idiolect summary mined from her own writing (email).

IMPORTANT — offline constraint: the era/region datasets below are authored
*offline* during development and shipped as static data. Nothing here calls the
internet at runtime; the Spark stays air-gapped. The local model already
encodes most era/region knowledge, so a profile is a concise steer, not a
scraped corpus.

Because there is exactly one user per deployment, the composed system prompt is
constant — so vLLM still prefix-caches it and TTFT stays low.
"""
from __future__ import annotations

from dataclasses import dataclass

# Language is imprinted most strongly in adolescence/early adulthood. We treat
# birth_year + this offset as the center of the "formative" linguistic window.
FORMATIVE_OFFSET = 15


@dataclass
class Profile:
    name: str | None = None
    birth_year: int | None = None
    region: str | None = None          # key into REGION_PROFILES, or free text
    idiolect_notes: str | None = None   # phase 2: summary mined from her email

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "birth_year": self.birth_year,
            "region": self.region,
            "idiolect_notes": self.idiolect_notes,
        }

    @classmethod
    def from_dict(cls, d: dict | None) -> "Profile":
        d = d or {}
        return cls(
            name=d.get("name"),
            birth_year=d.get("birth_year"),
            region=d.get("region"),
            idiolect_notes=d.get("idiolect_notes"),
        )


# ── Era profiles ─────────────────────────────────────────────────────────────
# Keyed by the *formative decade* (birth_year + FORMATIVE_OFFSET, floored to a
# decade). Each entry is a short steer on register, warmth, and a few era-true
# turns of phrase — deliberately modest. These are authored guidance for the
# model, not an exhaustive lexicon, and are meant to bias tone, not to costume.
ERA_PROFILES: dict[int, str] = {
    1940: (
        "Her formative years were the 1940s. Favor warm, gracious, somewhat "
        "formal phrasing. Courtesies like \"please\", \"thank you kindly\", and "
        "\"I'd be much obliged\" fit naturally. Understated about discomfort "
        "(\"I'm not quite myself today\"). Avoid modern slang entirely."
    ),
    1950: (
        "Her formative years were the 1950s. Polite, friendly, a little formal. "
        "Gentle expressions like \"oh my\", \"goodness\", \"that would be lovely\", "
        "\"I'd appreciate it\". Modest and uncomplaining in tone. No modern slang."
    ),
    1960: (
        "Her formative years were the 1960s. Warm and plain-spoken with an easy, "
        "informal friendliness. \"That's fine\", \"I'd love that\", \"no trouble at "
        "all\" fit well. Sincere rather than effusive. Avoid 21st-century idioms."
    ),
    1970: (
        "Her formative years were the 1970s. Relaxed, direct, and warm. Casual "
        "phrasing like \"that's great\", \"I really need...\", \"thanks so much\" "
        "fits. Comfortable and unfussy. Avoid current internet-era slang."
    ),
    1980: (
        "Her formative years were the 1980s. Friendly, conversational, direct. "
        "Everyday phrasing like \"I'd really like...\", \"that works for me\", "
        "\"thanks a lot\". Keep it natural and contemporary to that era."
    ),
    1990: (
        "Her formative years were the 1990s. Casual, warm, straightforward "
        "everyday English. Keep phrasing natural and unforced."
    ),
}
_DEFAULT_ERA = (
    "Use natural, warm, everyday English. Keep phrasing plain, sincere, and "
    "easy to recognize."
)

# ── Region profiles ──────────────────────────────────────────────────────────
# Light dialect/register steer. Free-text regions fall through to a generic note.
REGION_PROFILES: dict[str, str] = {
    "us-south": (
        "She is from the American South; gentle Southern warmth fits "
        "(\"y'all\", \"bless you\", \"I reckon\", \"sugar\") — used sparingly and "
        "only where it sounds natural."
    ),
    "us-northeast": (
        "She is from the American Northeast; plain, direct, unsentimental warmth."
    ),
    "us-midwest": (
        "She is from the American Midwest; friendly, modest, understated "
        "(\"oh, that's no bother\", \"you bet\")."
    ),
    "us-west": (
        "She is from the American West; easygoing, informal, warm."
    ),
    "uk": (
        "She is British; understated, polite phrasing fits (\"lovely\", \"I'm "
        "quite alright\", \"would you mind...\"). Avoid Americanisms."
    ),
}


def formative_decade(birth_year: int) -> int:
    return ((birth_year + FORMATIVE_OFFSET) // 10) * 10


def _era_guidance(birth_year: int | None) -> str:
    if not birth_year:
        return _DEFAULT_ERA
    decade = formative_decade(birth_year)
    # Clamp to the available range so very old/young years still get a steer.
    keys = sorted(ERA_PROFILES)
    decade = min(max(decade, keys[0]), keys[-1])
    return ERA_PROFILES.get(decade, _DEFAULT_ERA)


def _region_guidance(region: str | None) -> str:
    if not region:
        return ""
    key = region.strip().lower().replace(" ", "-")
    if key in REGION_PROFILES:
        return REGION_PROFILES[key]
    return f"She is from {region.strip()}; let that place gently color the phrasing."


def compose_system_prompt(base_prompt: str, profile: Profile) -> str:
    """Append a persona section to the base prompt. Deterministic ordering so
    the result is byte-stable across requests (preserves prefix caching)."""
    if not profile or not (profile.birth_year or profile.region or profile.idiolect_notes):
        return base_prompt

    lines = ["", "Voice and idiom:"]
    who = "She"
    if profile.name:
        who = profile.name
        lines.append(f"- Her name is {profile.name}.")
    if profile.birth_year:
        lines.append(
            f"- {who} was born in {profile.birth_year}. In Alzheimer's, "
            "early-learned language is the most preserved and the most "
            "recognizable to her as her own."
        )
    era = _era_guidance(profile.birth_year)
    if era:
        lines.append(f"- {era}")
    region = _region_guidance(profile.region)
    if region:
        lines.append(f"- {region}")
    if profile.idiolect_notes:
        lines.append(
            "- Her own characteristic phrasing (from her writing): "
            f"{profile.idiolect_notes.strip()}"
        )
    lines.append(
        "- Treat all of the above as a gentle bias on tone, warmth, formality, "
        "and word choice — not as costume. Never force dated slang or "
        "caricature. Clarity for the listener always comes first."
    )
    return base_prompt + "\n" + "\n".join(lines)
