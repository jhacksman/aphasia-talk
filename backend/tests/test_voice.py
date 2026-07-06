"""Cloned-voice endpoints: reference upload, status, and TTS (mock mode)."""
import io
import struct
import wave


def _wav_bytes(seconds: float = 4.0, rate: int = 16000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<" + "h" * int(rate * seconds), *([0] * int(rate * seconds))))
    return buf.getvalue()


def test_voice_status_empty_by_default(client):
    status = client.get("/voice").json()
    assert status["cloned_available"] is False


def test_upload_reference_wav_autotranscribes(client):
    resp = client.post(
        "/voice/reference",
        files={"audio": ("grandma.wav", _wav_bytes(), "audio/wav")},
    )
    assert resp.status_code == 200, resp.text
    status = resp.json()
    assert status["cloned_available"] is True
    # Mock whisper transcribes everything as "water".
    assert status["transcript"] == "water"
    assert status["original_filename"] == "grandma.wav"
    assert status["duration_seconds"] >= 3.9

    # Status persists for the Settings sheet.
    assert client.get("/voice").json()["cloned_available"] is True


def test_upload_reference_with_manual_transcript(client):
    resp = client.post(
        "/voice/reference",
        files={"audio": ("clip.wav", _wav_bytes(), "audio/wav")},
        data={"transcript": "Hello dear, it's me."},
    )
    assert resp.status_code == 200
    assert resp.json()["transcript"] == "Hello dear, it's me."


def test_upload_rejects_wrong_type_and_short_clips(client):
    resp = client.post(
        "/voice/reference",
        files={"audio": ("notes.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 400

    resp = client.post(
        "/voice/reference",
        files={"audio": ("blip.wav", _wav_bytes(seconds=1.0), "audio/wav")},
    )
    assert resp.status_code == 400
    assert "too short" in resp.json()["detail"]


def test_tts_409_without_reference(client):
    # Same contract in mock and real mode: no uploaded reference -> 409,
    # which is exactly what drives the tablet's fallback to the fast voice.
    resp = client.post("/tts", json={"text": "I would like some tea."})
    assert resp.status_code == 409


def test_tts_returns_wav_after_reference_upload(client):
    client.post(
        "/voice/reference",
        files={"audio": ("grandma.wav", _wav_bytes(), "audio/wav")},
    )
    resp = client.post("/tts", json={"text": "I would like some tea."})
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "audio/wav"
    assert resp.content[:4] == b"RIFF"


def test_tts_rejects_empty_text(client):
    assert client.post("/tts", json={"text": "  "}).status_code == 422
