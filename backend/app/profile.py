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
# decade). Each entry steers *register only* — formality, warmth, and avoiding
# anachronistic modern slang. Deliberately no catchphrases, no quoted "period"
# expressions, no dialect spelling: the goal is a real person speaking
# naturally, lightly inflected by when they grew up — never a costume.
ERA_PROFILES: dict[int, str] = {
    1940: (
        "She grew up in the 1940s. Her phrasing leans slightly formal and "
        "courteous, in complete sentences. Keep vocabulary timeless; avoid "
        "modern slang and internet-era phrasing."
    ),
    1950: (
        "She grew up in the 1950s. Her phrasing is warm and polite, a touch "
        "formal. Use plain mid-century everyday vocabulary; avoid modern slang."
    ),
    1960: (
        "She grew up in the 1960s. Her phrasing is warm and plain-spoken, "
        "relaxed but not slangy. Avoid 21st-century idioms."
    ),
    1970: (
        "She grew up in the 1970s. Her phrasing is relaxed, direct, and warm — "
        "ordinary everyday English. Avoid current internet-era slang."
    ),
    1980: (
        "She grew up in the 1980s. Her phrasing is friendly and conversational, "
        "plain everyday English. Avoid trendy current slang."
    ),
    1990: (
        "She grew up in the 1990s. Her phrasing is casual, warm, and "
        "straightforward. Keep it natural and unforced."
    ),
}
_DEFAULT_ERA = "Use natural, warm, everyday English. Keep phrasing plain and realistic."

# ── Region profiles ──────────────────────────────────────────────────────────
# A very light register note only. No dialect tokens or stock phrases — the
# sentences must still sound like a real person, not a regional impression.
REGION_PROFILES: dict[str, str] = {
    "us-south": "She is from the American South; a gentle, warm register fits — but keep it natural, with no heavy dialect or stock phrases.",
    "us-northeast": "She is from the American Northeast; plain, direct warmth.",
    "us-midwest": "She is from the American Midwest; friendly, modest, understated.",
    "us-west": "She is from the American West; easygoing and informal.",
    "uk": "She is British; phrasing skews a little more understated and formal than American English. Avoid heavy dialect.",
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
        "- Apply the above as a very light touch on register only. The sentences "
        "must sound like a real person speaking naturally — never a period "
        "performance, never dialect spelling, catchphrases, or dated slang. When "
        "in doubt, phrase it plainly. Realism and clarity come first."
    )
    return base_prompt + "\n" + "\n".join(lines)
