# Proposal: Ask mode — question capture + contextual replies

**Status: PROPOSED, not implemented.** (2026-07-02, drafted on gb10-02.)

## The problem

Today the app is one-directional: she initiates by tapping a word. But most
real conversation is the other direction — a caregiver or family member asks
her a question ("Are you hungry?", "Did you sleep okay?", "Do you want to
call Susan?") and she has no good way to answer it. Word-tap sentences are
generated with no knowledge of the question, so even a good sentence is
often a non-sequitur.

Goal: capture what was said to her, show it as text she can tap, and
generate candidate **replies** that fit the question — while keeping a short
conversation log so all generation is contextually appropriate.

## The core design decision: push-to-listen, not always-on

The obvious version — an always-on microphone transcribing the room — is
rejected. Three reasons, each sufficient alone:

1. **The TV problem is unsolvable in that mode.** TV/radio dialogue *is*
   speech; no voice-activity detector can filter it. Distinguishing "family
   member speaking to her" from "actor speaking on screen" requires speaker
   diarization + enrollment of every family voice, and it still fails on
   phone calls, visitors, and her own TV shows. A log polluted with TV
   dialogue makes generation *worse*, not better — the model would answer
   the soap opera.
2. **Privacy/consent.** An always-listening device in the home of a person
   with Alzheimer's records visitors, phone calls, and private family
   moments. Even fully local, that's a surveillance posture this project
   shouldn't have.
3. **Reliability and calm beat features** (CLAUDE.md, line one). An ambient
   pipeline is a research project; a bounded one is a weekend of work on
   parts that already exist and are smoke-tested.

Instead: **the caregiver deliberately captures the question.** They tap an
"Ask" button, speak, tap again (exactly the interaction her Dictate button
already has). The audio window is a few seconds long and intentional:

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
   ↓ she taps it (or ignores it — nothing forces her)
Sentence list fills with candidate REPLIES (~2s):
   “Yes, I would like something to eat.”
   “No thank you, not right now.”
   “Maybe a little later.”
   “I would rather have something to drink.”
   “I am not sure. What do we have?”
   ↓ she taps one → tablet speaks it → logged as her turn
```

Two properties matter more than they look:

- **Reply candidates must span the answer space** — affirmative, negative,
  deferral, redirect, emotional — because the system cannot know her actual
  answer. Generating six variants of "yes" would put words in her mouth;
  that violates the dignity invariant more subtly than condescension does.
  This is a prompt requirement, and the thing to judge hardest in tuning.
- **The question is an offer, not a mode.** If she ignores the strip and
  taps a grid word instead, nothing is lost — and generation for that word
  quietly knows the recent question (see context below), so tapping "water"
  after "Are you hungry?" yields "No, but I am thirsty"-shaped options.

## Conversation log

New SQLite table:

```sql
CREATE TABLE conversation_turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL,        -- 'heard' (transcribed to her) | 'spoken' (she spoke via TTS)
    text TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

- `heard` turns written when an Ask transcription succeeds.
- `spoken` turns written by the existing `/speak-log` hook (it already
  receives every sentence she speaks — one extra insert).
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
| `POST /ask` (new) | multipart audio → transcribe via whisper, reject garbage (below), insert `heard` turn, return `{text, turn_id}`. Kept separate from `/transcribe` so her Dictate semantics don't change. |
| `POST /respond` (new) | `{question}` → reply candidates + related words, same response shape as `/generate` (clients reuse the sentence list untouched). Prompt: her persona + conversation window + "generate replies spanning yes/no/deferral/redirect/emotional; never presume her answer." |
| `POST /generate` | backend-side only: append recent `heard` turn(s) inside the window to the user prompt ("A moment ago she was asked: …"). No client change, no schema change. |
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
  for the person talking with her: tap, ask your question, tap again."
- **Question strip**: a *permanently reserved*, fixed-height row between the
  output bar and the word grid. Empty state is a quiet placeholder; when a
  question arrives it shows large tappable text. Because the space is always
  reserved, nothing on screen ever shifts — grid and buttons stay put.
  Nothing about it auto-dismisses (invariant 5); a new question replaces the
  old, and Clear empties it.
- Tapping the strip calls `/respond` and fills the existing sentence list;
  bookmarking/speaking work unchanged.

## Deferred, not rejected: her name as the wake word (phase 3)

A generic wake word ("Hey Talk, …") was rejected: artificial phrase nobody
remembers mid-conversation, TV-triggered false accepts that change her
screen unpredictably, and the endpointing problem all over again.

Jack's refinement — **her own name as the wake word** ("Hey Margaret, are
you hungry?") — is much stronger and is the designated shape for hands-free
capture if field use demands it:

- It is how family already addresses her; nothing artificial to remember.
- Her name in the audio is content-based diarization on the cheap: a real
  signal the speech is directed *at* her rather than at/from the TV.

Remaining problems, and the mitigation that makes them acceptable:

- **Speech *about* her fires it** ("Margaret seemed tired today") — third-
  person conversation must never surface on her screen as a tappable card.
- Her name said **on TV**; **follow-up questions without the name** never
  trigger (partial capture); diminutives (Mom, Grandma, …) each need their
  own wake model; short names make weak keywords.
- Always-on mic posture on the tablet (battery, permission), and VAD
  endpointing in a noisy room.

**The LLM gate**: wake fires → record with VAD endpoint → transcribe →
one cheap local-LLM classification — *"is this a question or request
addressed directly to her, in the second person?"* — and everything that
fails is **silently discarded** (never shown, never logged). That flips the
harm model: false accepts become invisible discards; only high-confidence
real questions touch her screen. Speech-about-her and most TV dialogue die
at the gate.

Still phase 3, not v1: the core loop (log, /respond, reply tuning, strip)
is identical work either way and ships without wake-model training,
endpointing, and gate-threshold tuning — all of which need field iteration
on a pipeline that already works. Push-to-talk first; bolt the hands-free
trigger onto a proven path. The caregiver-phone client (step 4) covers the
across-the-room case in the meantime.

## What this deliberately does NOT do

- No always-on microphone in v1; "hey $name" wake capture is phase 3 (above).
- No speaker diarization/enrollment — unnecessary once capture is intentional.
- No auto-generation on transcription — the question waits until *she* taps.
- No auto-selected or pre-highlighted reply — all candidates are equal;
  choosing is hers.
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
4. **Later, only if field use demands**: trailing-silence auto-stop for the
   caregiver's recording, whisper VAD flag, a caregiver-phone companion
   page (the web client on their phone already covers most of this), and
   the "hey $name" wake capture with the LLM gate (section above).

## Open questions for Jack

1. Button label: "Ask" vs "Question" vs a family word for it?
2. Retention default (proposed 7 days) and whether family wants the log
   viewable at all, or fire-and-forget?
3. Should a fresh question *replace* the strip content silently, or should
   the strip show the last 2-3 questions scrollable? (Proposed: just the
   latest — one clear thing to tap.)
