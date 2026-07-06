#!/usr/bin/env bash
# End-to-end smoke test against the REAL stack (vLLM + whisper.cpp + backend).
# Run on the Spark after `docker compose up -d`. Fails loudly on any problem.
set -uo pipefail

BACKEND="${BACKEND:-http://127.0.0.1:8080}"
VLLM="${VLLM:-http://127.0.0.1:8000}"
FAIL=0

say()  { printf '\n== %s\n' "$*"; }
ok()   { printf '   OK  %s\n' "$*"; }
bad()  { printf '   FAIL %s\n' "$*"; FAIL=1; }

# --- vLLM up and serving a model (name is config, not hardcoded) ------------
say "vLLM /v1/models"
MODELS=$(curl -sS -m 10 "$VLLM/v1/models" || true)
LOADED=$(echo "$MODELS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || true)
if [ -n "$LOADED" ]; then
    ok "model loaded: $LOADED"
    if [ -n "${VLLM_MODEL:-}" ] && [ "$LOADED" != "$VLLM_MODEL" ]; then
        bad "loaded model ($LOADED) != VLLM_MODEL ($VLLM_MODEL) — compose and env out of sync"
    fi
else
    bad "vLLM not up or no model loaded. Response: ${MODELS:0:200}"
fi

# --- backend health, must NOT be in mock mode -------------------------------
say "backend /health"
HEALTH=$(curl -sS -m 10 "$BACKEND/health" || true)
echo "   $HEALTH"
echo "$HEALTH" | grep -q '"status":"ok"' && ok "backend up" || bad "backend not healthy"
if echo "$HEALTH" | grep -q '"mock_inference":true'; then
    bad "MOCK_INFERENCE is still true — this is the test backend, not the real one"
else
    ok "real inference mode"
fi

# --- word grid ---------------------------------------------------------------
say "backend /words"
curl -sS -m 10 "$BACKEND/words" | python3 -c '
import json,sys
d=json.load(sys.stdin)
cats=[c["name"] for c in d["categories"]]
assert len(cats)>=6, cats
print(f"   OK  {len(cats)} categories: {cats}")' || bad "/words failed"

# --- real generation with latency -------------------------------------------
say "backend /generate (word: water) — REAL model, timed"
START=$(date +%s.%N)
GEN=$(curl -sS -m 60 -X POST "$BACKEND/generate" \
      -H 'Content-Type: application/json' \
      -d '{"word":"water","category":"Needs"}' || true)
ELAPSED=$(python3 -c "import time; print(f'{$(date +%s.%N)-$START:.2f}')")
echo "$GEN" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x["text"] for x in d["sentences"]]
assert len(s)>=4, f"only {len(s)} sentences"
assert all(len(x.split())<=20 for x in s), "sentences too long for TTS"
rw=d["related_words"]
print(f"   OK  {len(s)} sentences, {len(rw)} related words")
for x in s[:4]: print(f"        - {x}")' \
  && ok "generation latency: ${ELAPSED}s (target < ~2.5s warm)" \
  || bad "/generate failed or malformed: ${GEN:0:300}"

# Second call should hit the prefix cache and be faster.
say "backend /generate again (prefix-cache warm check)"
START=$(date +%s.%N)
curl -sS -m 60 -X POST "$BACKEND/generate" \
     -H 'Content-Type: application/json' \
     -d '{"word":"tired","category":"Feelings"}' >/dev/null || bad "second generate failed"
ELAPSED2=$(python3 -c "import time; print(f'{$(date +%s.%N)-$START:.2f}')")
ok "warm latency: ${ELAPSED2}s"

# --- vision with a real (tiny) image ----------------------------------------
say "backend /vision (1x1 test JPEG — expects a graceful answer, not a 500)"
python3 - <<'EOF'
# Minimal valid JPEG so the model gets a decodable image.
import base64
jpeg = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACv/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==")
open("/tmp/aphasia_test.jpg","wb").write(jpeg)
EOF
VIS=$(curl -sS -m 90 -X POST "$BACKEND/vision" -F "image=@/tmp/aphasia_test.jpg;type=image/jpeg" || true)
echo "$VIS" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "identified_object" in d, d
obj=d["identified_object"]; sents=d["sentences"]
print(f"   OK  identified: {obj!r}, {len(sents)} sentences")' \
  || bad "/vision failed: ${VIS:0:300}"

# --- transcription with a real WAV ------------------------------------------
say "backend /transcribe (1s silence WAV — expects 2xx, not a crash)"
python3 - <<'EOF'
import struct, wave
w = wave.open("/tmp/aphasia_test.wav", "w")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
w.writeframes(struct.pack("<" + "h"*16000, *([0]*16000)))
w.close()
EOF
TR=$(curl -sS -m 60 -X POST "$BACKEND/transcribe" -F "audio=@/tmp/aphasia_test.wav;type=audio/wav" || true)
echo "$TR" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=d["text"]; print(f"   OK  transcribed: {t!r}")' \
  || bad "/transcribe failed: ${TR:0:300}"

# --- cloned voice ------------------------------------------------------------
say "backend /voice (cloned-voice status)"
VOICE=$(curl -sS -m 10 "$BACKEND/voice" || true)
echo "$VOICE" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d["cloned_available"]; print(f"   OK  cloned_available={v}")' \
  || bad "/voice failed: ${VOICE:0:200}"

say "backend /tts (200 with reference, 409 without — 5xx means the sidecar is broken)"
TTS_CODE=$(curl -sS -m 120 -o /tmp/aphasia_tts_out.wav -w "%{http_code}" \
    -X POST "$BACKEND/tts" -H 'Content-Type: application/json' \
    -d '{"text":"Hello, this is a voice test."}' || echo "000")
if [ "$TTS_CODE" = "200" ]; then
    head -c 4 /tmp/aphasia_tts_out.wav | grep -q RIFF \
      && ok "cloned voice speaking (WAV returned)" \
      || bad "/tts returned 200 but not a WAV"
elif [ "$TTS_CODE" = "409" ]; then
    ok "TTS wiring works — no reference uploaded yet (upload from tablet Settings)"
else
    bad "/tts returned HTTP $TTS_CODE — check: docker compose logs tts --tail 50"
fi

# --- bookmarks round trip ----------------------------------------------------
say "backend bookmark round-trip"
BM=$(curl -sS -m 10 -X POST "$BACKEND/bookmarks" -H 'Content-Type: application/json' \
     -d '{"text":"__smoke_test__","word":"__smoke__"}' || true)
BMID=$(echo "$BM" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)
if [ -n "${BMID:-}" ]; then
    curl -sS -m 10 -X DELETE "$BACKEND/bookmarks/$BMID" >/dev/null && ok "create+delete id=$BMID" || bad "delete failed"
else
    bad "bookmark create failed: ${BM:0:200}"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "ALL SMOKE TESTS PASSED — safe to point the tablet at this backend."
else
    echo "SMOKE TEST FAILURES — fix before touching the tablet. Logs:"
    echo "  docker compose logs backend --tail 50"
    echo "  docker compose logs vllm --tail 50"
    exit 1
fi
