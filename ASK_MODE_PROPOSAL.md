# Ask mode — question capture + contextual replies

**Status: phase 1 BUILT (2026-07-03) — backend + web + Flutter UI, all
tests green, verified live on gb10-02.** Wake-word capture (phase 2)
is unblocked: the default wake phrase is "hey there" (see below), and
the server-side LLM gate is built and live.

Implementation notes beyond this design: `/ask` also accepts a typed
question (form field `text`) for mic-less clients and loud rooms; whisper.cpp
was observed to crash on its first inference after a long idle (GB10 CUDA
error), so `/ask` retries once over the container's ~15s auto-restart before
returning the calm empty answer.

## The problem

Today the app is one-directional: the user initiates by tapping a word. But
most real conversation is the other direction — a caregiver or family member
asks a question ("Are you hungry?", "Did you sleep okay?", "Do you want to
call Susan?") and the user has no good way to answer it. Word-tap sentences are
generated with no knowledge of the question, so even a good sentence is
often a non-sequitur.

Goal: capture what was said to the user, show it as text they can tap, and
generate candidate **replies** that fit the question — while keeping a short
conversation log so all generation is contextually appropriate.

## The core design decision: intentional capture, not ambient transcription

Two capture triggers, one pipeline:

1. **v1: push-to-talk** — the caregiver taps an [Ask] button, asks, taps
   again. Deterministic; ships the whole loop with parts that already exist.
2. **Phase 2: wake phrase "hey there"** — hands-free, spotted by a tiny
   on-device model (see the wake-word section). Not always-on listening:
   audio passes through the spotter in RAM and is discarded; nothing is
   recorded or transcribed until the phrase fires.

What stays rejected is **ambient transcription** — a microphone
transcribing the room continuously. Three reasons, each sufficient alone:

1. **The TV problem is unsolvable in that mode.** TV/radio dialogue *is*
   speech; no voice-activity detector can filter it. Distinguishing "family
   member speaking to the user" from "actor speaking on screen" requires speaker
   diarization + enrollment of every family voice, and it still fails on
   phone calls, visitors, and the user's own TV shows. A log polluted with TV
   dialogue makes generation *worse*, not better — the model would answer
   the soap opera.
2. **Privacy/consent.** An always-listening device in the home of a person
   with Alzheimer's records visitors, phone calls, and private family
   moments. Even fully local, that's a surveillance posture this project
   shouldn't have.
3. **Reliability and calm beat features** (CLAUDE.md, line one). An ambient
   pipeline is a research project; a bounded one is a weekend of work on
   parts that already exist and are smoke-tested.

Both triggers produce the same thing: a bounded, intentional audio window
a few seconds long. For the v1 button (exactly the interaction the Dictate
button already has):

- TV in the background of a 5-second near-field clip is something
  whisper large-v3-turbo handles well — it strongly favors the loud,
  close voice.
- The transcript is **shown to the caregiver before anything acts on it**.
  A human reads it; if the TV won, they tap Ask and repeat the question.
  Human review is the noise filter no VAD can match.
- Zero recording happens outside those seconds.

## User flow

```
Caregiver: taps [Ask] → asks "Are you hungry?" → taps again
   ↓ (~1s whisper + log turn)
Question strip shows:  💬 “Are you hungry?”        (large, tappable)
   ↓ the user taps it (or ignores it — nothing forces them)
Sentence list fills with candidate REPLIES (~2s):
   “Yes, I would like something to eat.”
   “No thank you, not right now.”
   “Maybe a little later.”
   “I would rather have something to drink.”
   “I am not sure. What do we have?”
   ↓ they tap one → tablet speaks it → logged as their turn
```

Two properties matter more than they look:

- **Reply candidates must span the answer space** — affirmative, negative,
  deferral, redirect, emotional — because the system cannot know the user's
  actual answer. Generating six variants of "yes" would put words in their mouth;
  that violates the dignity invariant more subtly than condescension does.
  This is a prompt requirement, and the thing to judge hardest in tuning.
- **The question is an offer, not a mode.** If the user ignores the strip and
  taps a grid word instead, nothing is lost — and generation for that word
  quietly knows the recent question (see context below), so tapping "water"
  after "Are you hungry?" yields "No, but I am thirsty"-shaped options.

## Conversation log

New SQLite table:

```sql
CREATE TABLE conversation_turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL,        -- 'heard' (transcribed to the user) | 'spoken' (user spoke via TTS)
    text TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

- `heard` turns written when an Ask transcription succeeds.
- `spoken` turns written by the existing `/speak-log` hook (it already
  receives every sentence the user speaks — one extra insert).
- **Context window**: prompts include only the last ~6 turns AND only turns
  from the last ~5 minutes. A question from this morning must not color an
  afternoon reply; stale context is worse than none.
- **Invariant 2 is preserved**: the context block goes in the *user*
  message. The system prompt stays byte-stable; prefix caching is untouched.
- Retention: prune rows older than N days (default 7) at startup; a
  caregiver "Clear conversation" action wipes the table. This is a working
  buffer, not an archive.

## API changes (backend)

| Endpoint | Change |
|---|---|
| `POST /ask` (new) | multipart audio → transcribe via whisper, reject garbage (below), insert `heard` turn, return `{text, turn_id}`. Kept separate from `/transcribe` so Dictate semantics don't change. |
| `POST /respond` (new) | `{question}` → reply candidates + related words, same response shape as `/generate` (clients reuse the sentence list untouched). Prompt: the user's persona + conversation window + "generate replies spanning yes/no/deferral/redirect/emotional; never presume their answer." |
| `POST /generate` | backend-side only: append recent `heard` turn(s) inside the window to the user prompt ("A moment ago someone asked them: …"). No client change, no schema change. |
| `POST /speak-log` | also insert a `spoken` conversation turn. |
| `GET /conversation` | recent turns (for the strip after app restart, and for caregiver review). |
| `DELETE /conversation` | the Clear action. |

Garbage rejection in `/ask` (server-side, cheap):

- empty/whitespace transcript → 200 with `{text: ""}`; client shows the calm
  "I didn't catch that — tap Ask and try again" state (to the *caregiver*)
- known whisper silence-hallucinations dropped ("Thanks for watching.",
  "Subtitles by …", repeated single tokens)
- hard cap on clip length (~30 s) to bound whisper latency
- temperature already 0.0; optionally enable whisper.cpp's Silero VAD flag
  later if real-world clips need it — decide from field behavior, not upfront

## UI changes (mobile + web)

- **[Ask] button** appended to the input bar *after* Dictate/Photo/Keyboard.
  Existing buttons keep their exact positions (invariant 1). Distinct color;
  semantics label makes clear it's for the conversation partner: "Ask —
  for the conversation partner: tap, ask your question, tap again."
- **Question strip**: a *permanently reserved*, fixed-height row between the
  output bar and the word grid. Empty state is a quiet placeholder; when a
  question arrives it shows large tappable text. Because the space is always
  reserved, nothing on screen ever shifts — grid and buttons stay put.
  Nothing about it auto-dismisses (invariant 5); a new question replaces the
  old, and Clear empties it.
- Tapping the strip calls `/respond` and fills the existing sentence list;
  bookmarking/speaking work unchanged.

## Wake-word capture (committed, phase 2)

The hands-free trigger is a wake phrase, **"hey there" by default** — a
fixed, deployment-independent phrase so the feature ships for anyone
without per-user model training. The wake phrase is config, not code
(invariant 6): a deployment can swap in the user's own name ("hey
Margaret") as a personalization later, which is even more natural — family
already say the name when addressing them — but nothing is blocked on it.

**This is not always-on listening.** A wake-word spotter is a tiny keyword
model running on the tablet; mic samples pass through it in RAM and are
discarded milliseconds later. Nothing is recorded, transcribed, stored, or
sent over the network until the keyword fires. The privacy posture is
categorically different from ambient transcription (which stays rejected).

Pipeline when it fires:

```
on-device spotter hears the wake phrase ("hey there")
  → capture starts from a ~2s pre-roll ring buffer (so the question
    isn't clipped if the phrase and question run together)
  → record until trailing silence (VAD endpoint)
  → POST /ask?gate=true (same path as the button, plus the gate)
  → LLM gate: "is this a question or request addressed directly to the
    user, in the second person?" — everything that fails is SILENTLY
    discarded: never shown, never logged
  → pass → question strip updates
```

**The LLM gate is what makes wake capture safe** — it is BUILT and live
(`/ask?gate=true`; `GATE_SYSTEM_PROMPT` + `is_directed_at_user` in
backend/app/llm.py; fails closed on any error). Failure modes and how they
land:

- Speech *about* the user ("she seemed tired today") → fires the spotter,
  dies at the gate (third person). Never touches the screen or the log.
- The wake phrase on TV or in ordinary greetings ("hey there!") → mostly
  dies at the gate (a bare greeting isn't a question); residual
  true-question-shaped lines are rare and visible in the strip.
- Spotter misfires on similar-sounding audio → gate discards; cost is
  invisible.
- False *rejects* (missed phrase, follow-up questions asked without it)
  → the Ask button is the fallback; deterministic capture always works.
  Threshold the spotter toward false-reject: misfires are the harm,
  repeats are tolerable.

Implementation notes (the remaining phase-2 work is client-side):

- Spotter on-device in Flutter: Porcupine custom keyword ("hey there",
  swappable per deployment) or a tflite micro-wake-word model. On-device is
  a hard requirement — running detection on the Spark would mean streaming
  tablet audio continuously, which is the ambient posture we rejected.
- Personalization option: additionally train the user's name/what family
  calls them (Mom, Grandma, …). Short names make weaker keywords; test
  false-accept rates against recorded TV audio.
- The tablet lives docked/plugged as a communication device, so the
  continuous-spotter battery cost is largely moot; still expose a settings
  toggle (wake capture on/off) for unplugged use.
- The spotter bolts onto the proven /ask?gate=true → strip pipeline;
  gate/threshold tuning iterates against the live stack.

## What this deliberately does NOT do

- No ambient transcription, ever. Wake capture ("hey there", phase 2) spots
  a keyword on-device and discards everything else unheard.
- No speaker diarization/enrollment — unnecessary once capture is intentional.
- No auto-generation on transcription — the question waits until the *user* taps.
- No auto-selected or pre-highlighted reply — all candidates are equal;
  choosing is theirs.
- No transcripts in the system prompt (invariant 2).
- Log never leaves the box (invariant 3).

## Cost estimates

- Latency: stop-tap → transcript ~1 s (turbo on GB10); tap question →
  replies ~2 s warm (same path as /generate). Within budget.
- Scope: backend ~200 lines + tests (mock-inference paths included, so CI
  needs no GPU); Flutter: one button + one widget + two api calls; web
  client mirrors it first as the cheap testbed.

## Build order

1. **Backend**: table + `/ask` + `/respond` + context in `/generate` +
   `/speak-log` insert + pruning + tests. Exercisable end-to-end in the web
   client immediately.
2. **Web frontend**: Ask button + strip (the tuning surface — judge reply
   quality across question types here: yes/no, open, choice, emotional).
3. **Flutter app**: same UI, reusing the existing recorder plumbing.
4. **Wake capture (phase 2)**: on-device "hey $name" spotter + pre-roll
   buffer + VAD endpoint + the LLM gate (section above). Requires the core
   loop live to tune gate and thresholds against.
5. **Later, only if field use demands**: trailing-silence auto-stop for the
   button flow, whisper VAD flag, a caregiver-phone companion page (the web
   client on their phone already covers most of this).

## Open questions for Jack

1. Button label: "Ask" vs "Question" vs a family word for it?
2. Retention default (proposed 7 days) and whether family wants the log
   viewable at all, or fire-and-forget?
3. Should a fresh question *replace* the strip content silently, or should
   the strip show the last 2-3 questions scrollable? (Proposed: just the
   latest — one clear thing to tap.)
4. (Optional, per deployment) the user's name + what family actually calls
   them (Mom? Grandma? a nickname?) — for the profile, and to add
   personalized wake-phrase variants beyond the default "hey there".
