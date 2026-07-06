"""End-to-end tests for the public API (mock-inference mode).

These exercise routing, request/response shapes, SQLite persistence, the
bookmark-pinning rule, and the linguistic-profile composition. They do NOT
exercise real model output — that requires the DGX Spark stack and is out of
scope for CI.
"""
from app.seed import SEED_WORDS


def test_health(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["mock_inference"] is True


def test_words_grid_shape_and_stable_positions(client):
    data = client.get("/words").json()
    names = [c["name"] for c in data["categories"]]
    assert names == list(SEED_WORDS.keys())  # seed order preserved
    for cat in data["categories"]:
        assert cat["color"].startswith("#")
        seen_positions = set()
        for w in cat["words"]:
            assert w["text"] and w["icon"]
            pos = tuple(w["position"])
            assert pos not in seen_positions  # no two words share a slot
            seen_positions.add(pos)


def test_generate_returns_sentences_and_related(client):
    data = client.post("/generate", json={"word": "water", "category": "Needs"}).json()
    assert len(data["sentences"]) >= 4
    assert all("text" in s and "bookmarked" in s for s in data["sentences"])
    assert len(data["related_words"]) >= 1


def test_generate_unknown_word_still_generates(client):
    data = client.post("/generate", json={"word": "garden"}).json()
    assert len(data["sentences"]) >= 4
    assert data["related_words"]


def test_generate_rejects_empty_word(client):
    assert client.post("/generate", json={"word": ""}).status_code == 422


def test_bookmark_crud(client):
    created = client.post(
        "/bookmarks", json={"text": "I am thirsty.", "word": "water"}
    ).json()
    assert created["id"] > 0
    listed = client.get("/bookmarks").json()["bookmarks"]
    assert any(b["text"] == "I am thirsty." for b in listed)
    assert client.delete(f"/bookmarks/{created['id']}").json()["deleted"] == created["id"]
    assert client.delete("/bookmarks/99999").status_code == 404


def test_bookmarked_sentence_pins_to_top_and_is_flagged(client):
    client.post("/bookmarks", json={"text": "Please get me water.", "word": "water"})
    data = client.post("/generate", json={"word": "water"}).json()
    assert data["sentences"][0]["text"] == "Please get me water."
    assert data["sentences"][0]["bookmarked"] is True
    assert any(not s["bookmarked"] for s in data["sentences"])  # plus generated ones


def test_vision_returns_object_and_reflects_bookmarks(client):
    # The mock vision path identifies "cup"; bookmark one of its sentences first.
    gen = client.post("/generate", json={"word": "cup"}).json()
    first = gen["sentences"][0]["text"]
    client.post("/bookmarks", json={"text": first, "word": "cup"})
    vis = client.post(
        "/vision", files={"image": ("p.jpg", b"\xff\xd8\xff", "image/jpeg")}
    ).json()
    assert vis["identified_object"] == "cup"
    assert any(s["text"] == first and s["bookmarked"] for s in vis["sentences"])


def test_vision_rejects_empty_upload(client):
    assert client.post(
        "/vision", files={"image": ("p.jpg", b"", "image/jpeg")}
    ).status_code == 400


def test_transcribe(client):
    body = client.post(
        "/transcribe", files={"audio": ("a.wav", b"RIFFfake", "audio/wav")}
    ).json()
    assert body["text"] and 0.0 <= body["confidence"] <= 1.0


def test_profile_defaults_to_no_persona(client):
    p = client.get("/profile").json()
    assert p["birth_year"] is None
    assert "Voice and idiom" not in p["system_prompt_preview"]


def test_profile_set_composes_persona(client):
    r = client.put(
        "/profile", json={"name": "Margaret", "birth_year": 1948, "region": "us-south"}
    ).json()
    assert r["formative_decade"] == 1960  # 1948 + 15 -> 1963 -> 1960s
    preview = r["system_prompt_preview"]
    assert "Voice and idiom" in preview and "Margaret" in preview
    # No caricature tokens should leak into the steer.
    for token in ["y'all", "bless you", "i reckon", "oh my"]:
        assert token not in preview.lower()


def test_profile_name_only_still_has_persona(client):
    r = client.put("/profile", json={"name": "Margaret"}).json()
    assert "Margaret" in r["system_prompt_preview"]


def test_profile_pronouns_flow_into_prompt_and_default_neutral(client):
    r = client.put("/profile", json={"name": "Sam", "pronouns": "he/him"}).json()
    assert "pronouns are he/him" in r["system_prompt_preview"]
    # Without pronouns set, prompts stay neutral — no gendered wording.
    r2 = client.put("/profile", json={"name": "Sam", "pronouns": None}).json()
    preview = r2["system_prompt_preview"].lower()
    assert " she " not in preview and " her " not in preview and " he " not in preview


def test_profile_partial_update_preserves_idiolect(client):
    client.put("/profile", json={"idiolect_notes": "keeps it brief"})
    client.put("/profile", json={"name": "Margaret", "birth_year": 1948})
    p = client.get("/profile").json()
    assert p["idiolect_notes"] == "keeps it brief"  # not wiped by partial update
    assert p["name"] == "Margaret"


def test_profile_rejects_out_of_range_year(client):
    assert client.put("/profile", json={"birth_year": 1800}).status_code == 422


def test_ask_transcribes_and_logs_heard_turn(client):
    body = client.post(
        "/ask", files={"audio": ("q.wav", b"RIFFfake", "audio/wav")}
    ).json()
    assert body["text"]  # mock whisper output
    assert body["turn_id"] > 0
    turns = client.get("/conversation").json()["turns"]
    assert turns[0]["role"] == "heard" and turns[0]["text"] == body["text"]


def test_ask_accepts_typed_question(client):
    body = client.post("/ask", data={"text": "Do you want tea?"}).json()
    assert body["text"] == "Do you want tea?" and body["turn_id"] > 0


def test_ask_gate_discards_undirected_speech(client):
    """Wake-word path: speech that isn't a question directed at the user is
    silently dropped — never shown, never logged. (Mock gate: '?' heuristic.)"""
    body = client.post("/ask?gate=true", data={"text": "She seemed tired today."}).json()
    assert body["text"] == "" and body["turn_id"] is None
    assert client.get("/conversation").json()["turns"] == []

    body = client.post("/ask?gate=true", data={"text": "Are you hungry?"}).json()
    assert body["text"] == "Are you hungry?" and body["turn_id"] > 0


def test_ask_rejects_empty_upload(client):
    assert client.post(
        "/ask", files={"audio": ("q.wav", b"", "audio/wav")}
    ).status_code == 400
    assert client.post("/ask").status_code == 400  # neither audio nor text


def test_respond_returns_reply_spread(client):
    data = client.post("/respond", json={"question": "Are you hungry?"}).json()
    texts = [s["text"] for s in data["sentences"]]
    assert len(texts) >= 4
    # The mock mirrors the real prompt's requirement: yes and no both offered.
    assert any(t.lower().startswith("yes") for t in texts)
    assert any(t.lower().startswith("no") for t in texts)
    assert data["related_words"]


def test_respond_rejects_empty_question(client):
    assert client.post("/respond", json={"question": ""}).status_code == 422


def test_speak_log_records_spoken_turn(client):
    client.post("/speak-log", json={"text": "I am thirsty.", "word": "water"})
    turns = client.get("/conversation").json()["turns"]
    assert turns[0]["role"] == "spoken" and turns[0]["text"] == "I am thirsty."


def test_conversation_clear(client):
    client.post("/speak-log", json={"text": "I am thirsty.", "word": "water"})
    assert client.delete("/conversation").json()["cleared"] >= 1
    assert client.get("/conversation").json()["turns"] == []


def test_ask_retries_when_whisper_is_restarting(client, monkeypatch):
    """A crashed whisper (CUDA error after long idle) must yield one patient
    retry, then a calm empty answer — never a 500 at the caregiver."""
    import httpx

    import app.main as main
    from app import whisper

    monkeypatch.setattr(main, "_WHISPER_RETRY_DELAY_S", 0.0)
    calls = {"n": 0}

    async def flaky(data, fmt="wav"):
        calls["n"] += 1
        if calls["n"] == 1:
            raise httpx.RemoteProtocolError("Server disconnected")
        return "Are you hungry?", 0.9

    monkeypatch.setattr(whisper, "transcribe", flaky)
    body = client.post(
        "/ask", files={"audio": ("q.wav", b"RIFFfake", "audio/wav")}
    ).json()
    assert body["text"] == "Are you hungry?" and calls["n"] == 2

    async def dead(data, fmt="wav"):
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(whisper, "transcribe", dead)
    body = client.post(
        "/ask", files={"audio": ("q.wav", b"RIFFfake", "audio/wav")}
    ).json()
    assert body["text"] == "" and body["turn_id"] is None


def test_conversation_window_excludes_stale_turns(client):
    """Turns older than the context window must not reach prompts."""
    from app import db

    db.add_conversation_turn("heard", "Are you hungry?")
    with db._connect() as conn:  # age one turn past the window
        conn.execute(
            "UPDATE conversation_turns SET created_at = '2000-01-01T00:00:00Z'"
        )
    db.add_conversation_turn("heard", "Do you want tea?")
    window = db.recent_conversation_turns()
    assert [t["text"] for t in window] == ["Do you want tea?"]


def test_prompt_cache_reset_on_startup(client):
    # A composed prompt cached by one lifecycle must not leak into the next
    # (the DB may have been swapped/reseeded between them).
    import app.main as main

    client.put("/profile", json={"name": "Margaret", "birth_year": 1948})
    client.post("/generate", json={"word": "water"})  # populates the cache
    assert main._prompt_cache is not None

    from fastapi.testclient import TestClient

    with TestClient(main.app):
        assert main._prompt_cache is None
