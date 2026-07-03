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

## Alternative considered: wake word ("Hey Talk, are you hungry?")

Fairer than full ambient listening — nothing is transcribed until the
keyword fires — and it buys hands-free capture for a caregiver across the
room. Rejected for v1 anyway:

- **False accepts hurt *her*.** All wake-word engines misfire, and TV audio
  is the classic trigger. A misfire spontaneously changes the question strip
  on her screen to garbage she didn't cause — disorienting for someone with
  Alzheimer's, on a device whose contract is "calm, nothing surprises you."
  It also pollutes the conversation log.
- **Endpointing reintroduces the noise problem.** Push-to-talk gets exact
  boundaries from human intent; after a wake word the system must detect
  the question's end via trailing-silence VAD, which a TV keeps defeating.
- **False rejects are worse than a button.** A button works the first time,
  every time; a missed wake word means repeating yourself artificially.
- **Engineering posture**: on-device wake word in Flutter = Porcupine-class
  dependency + continuous mic permission + battery drain; running detection
  on the Spark instead would mean streaming tablet audio continuously —
  an always-on mic on the network, which is what we ruled out.

The hands-free need is mostly covered deterministically by the caregiver's
phone as a second client (build-order step 4). If field use still demands
voice initiation, add wake word later as **opt-in**, thresholded paranoidly
toward false-*reject* (misfires are the harm; repeats are tolerable).

## What this deliberately does NOT do

- No always-on microphone, no wake word in v1 (see above).
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
   page (the web client on their phone already covers most of this).

## Open questions for Jack

1. Button label: "Ask" vs "Question" vs a family word for it?
2. Retention default (proposed 7 days) and whether family wants the log
   viewable at all, or fire-and-forget?
3. Should a fresh question *replace* the strip content silently, or should
   the strip show the last 2-3 questions scrollable? (Proposed: just the
   latest — one clear thing to tap.)
