# Phase 0 — Decision Gate Plan

*Companion to `REMASTERING_PLAN.md` §7. Expands "Phase 0: Decision gate"
into an executable protocol informed by 2024–2025 transcriber research.*

---

## Table of contents

1. [What Phase 0 is for](#1-what-phase-0-is-for)
2. [Two questions, not one](#2-two-questions-not-one)
3. [Track selection](#3-track-selection)
4. [Tool selection — what changed since the parent plan](#4-tool-selection--what-changed-since-the-parent-plan)
5. [Pre-flight (free, no install)](#5-pre-flight-free-no-install)
6. [Protocol](#6-protocol)
7. [Listening protocol](#7-listening-protocol)
8. [Decision matrix](#8-decision-matrix)
9. [Time budget](#9-time-budget)
10. [Non-goals for Phase 0](#10-non-goals-for-phase-0)
11. [Outputs to keep](#11-outputs-to-keep)

---

## 1. What Phase 0 is for

Answer **the taste question** before committing a weekend to automation:
do you actually prefer the resynthesized output over Animenz's released
recording? Phase 0 produces no scripts, no library coverage, no manifest
— just one track end-to-end, mostly through GUIs, listened to carefully.

The parent plan's kill criterion lives here: if Phase 0's output doesn't
clearly beat the m4a (after the §9.1 mitigations), the project ends.

---

## 2. Two questions, not one

The original framing was one question — "does it sound better?" Two
questions are actually being answered, and they should be answered
independently because they have different failure modes:

**Q1 (taste): Does *resynthesis* sound better than the m4a?**
Tested with the audio-only path: m4a → transcriber → render. No PDF, no
OMR, no alignment. If the answer is no, the entire pipeline dies — the
PDFs can't rescue an aesthetic the listener doesn't like.

**Q2 (feasibility): Does Audiveris produce usable OMR for these PDFs?**
Tested independently on the same track's PDF. A "yes" here is what makes
Phase 2's 165-track batch tractable at quality. A "no" doesn't kill the
project but downgrades it to the audio-only path described in
`REMASTERING_PLAN.md` §4.1, which is a different and weaker thing.

Both questions get tested in Phase 0. They're independent, so the two
test paths can run in either order or in parallel.

---

## 3. Track selection

One track. Pick by *all* of these:

- **You know it cold.** Subjective comparison only works if you have a
  strong mental model of how the original sounds. A track you've heard
  300 times is the right input.
- **Mid-density.** Not the sparsest ballad (transcription is too easy
  to be informative) and not the fastest etude (everything will fail
  and you won't learn whose fault it is). Something with clear melody,
  some pedaling, occasional ornaments.
- **You have the PDF.** Rules out improvisations and live tracks
  without published sheets.
- **The PDF revision matches the recording.** If you're not sure, pick
  a different track. Mismatched revisions are §9.2 territory and
  contaminate the Q2 test.

A typical OP arrangement from a popular show (AoT, JJK, Frieren) is the
sweet spot. Avoid medleys — multiple show motifs in one PDF make OMR
output harder to verify by ear.

---

## 4. Tool selection — what changed since the parent plan

The parent plan said "ByteDance first, Transkun fallback." Recent work
shifts the landscape enough to revise that for Phase 0:

### 4.1 Transcriber: test two, not one

The 2024–2025 benchmarks split along an axis the parent plan didn't
consider — in-distribution vs. out-of-distribution performance.

| Model | MAESTRO note F1 | MAPS (OOD) F1 | Notes |
| --- | --- | --- | --- |
| **hFT-Transformer** (Sony AI, ISMIR 2023) | ~97 (highest published) | ~85 | Best on lab-quality recordings. PyTorch, 5.5 M params. |
| **Data-Driven Robust Piano Transcription** (2024) | 96.6 | **88.4** | Retrain of Kong/ByteDance with heavy augmentation. Best on real-world recordings. |
| **Kong et al. / ByteDance** (2021) | 96.7 | 82.4 | The model `piano_transcription_inference` ships. Models pedaling. |
| Transkun | — | — | Simpler CRF-based, easy to run. Fallback only. |

The MAESTRO–MAPS gap is what matters for Animenz audio. Animenz's
recordings are professionally captured but not Disklavier studio
recordings — they live somewhere on the spectrum between MAESTRO
conditions and MAPS conditions. Which model wins is *not* obvious from
benchmarks alone; it depends on the specific room/mic chain Animenz
records in.

So: run both **DDRPT** and **hFT-Transformer** on the Phase 0 track and
compare. Cost of running both is one-time download + ~1 min inference
each. Cheap. The winner becomes Phase 1's default.

ByteDance's original model is worth running too if DDRPT installation
is awkward — it's the same architecture, and the `piano_transcription_inference`
package is the most polished. The DDRPT checkpoint can be loaded into
the same architecture, so swapping the weights file is the actual
delta.

### 4.2 Renderer: still Salamander first, Pianoteq as upgrade

No change. Sfizz + Salamander V3 for Phase 0; switch to Pianoteq only
if §9.1 mitigations are needed.

### 4.3 OMR: still Audiveris

No change. The Q2 test specifically validates that Audiveris handles
Animenz's typesetting well enough for batch use.

---

## 5. Pre-flight (free, no install)

Before installing anything locally, spend 5 minutes on a commercial
service to confirm the audio is even transcribable in principle.

**Songscription** explicitly accepts M4A, free tier transcribes 30 s,
outputs MIDI. Upload the first 30 s of the chosen track, download the
MIDI, open it in any MIDI viewer (MuseScore, web-based piano-roll
viewer, anything).

This isn't a quality test — commercial services use older models and
their output is rarely as good as a local DDRPT run. It's a sanity
check: if even Songscription produces something recognizable, the audio
is in scope. If Songscription produces garbage, the recording has
something unusual (heavy compression, off-tuning, double-tracked piano)
that local models will also struggle with, and Phase 0 should account
for that before going further.

Alternative free previews if Songscription is down: Piano2Notes (first
20 s free), Eldoraudio. All wrap models from the same family.

This step is genuinely free — no install, no account required for the
short previews.

---

## 6. Protocol

Two parallel tracks, recombined at the listening step. Time estimates
assume reasonable familiarity with the command line; add ~30 min if
this is your first time with Python venvs.

### 6.1 Setup (~30 min)

```bash
# One-time
brew install ffmpeg sfizz audiveris    # macOS via Homebrew
mkdir phase0 && cd phase0
python3 -m venv .venv && source .venv/bin/activate
pip install piano_transcription_inference
# Salamander V3: download the SFZ pack manually from bigcatinstruments.com
#   (CC-BY-SA, ~1.9 GB), extract under ./SalamanderV3/
```

DDRPT checkpoint download: pull `note_F1=0.9677_pedal_F1=0.9186.pth`
from the Zenodo record (zenodo.org/records/10610212) into `./models/`.
The architecture matches `piano_transcription_inference`'s — load with
the package's API and override the checkpoint path.

### 6.2 Track A — Audio-only (the taste test) (~45 min)

```bash
# Step 1: m4a → wav
ffmpeg -i "001 - Track Title [vid].m4a" -ac 1 -ar 16000 audio.wav

# Step 2a: Run DDRPT
python -c "
from piano_transcription_inference import PianoTranscription, sample_rate, load_audio
audio, _ = load_audio('audio.wav', sr=sample_rate, mono=True)
transcriptor = PianoTranscription(checkpoint_path='models/ddrpt.pth')
transcriptor.transcribe(audio, 'perf_ddrpt.mid')
"

# Step 2b: Run hFT-Transformer (separate clone)
git clone https://github.com/sony/hFT-Transformer
# follow their README; output → perf_hft.mid

# Step 3: Render each MIDI through Salamander
for m in perf_ddrpt perf_hft; do
  sfizz_render -i $m.mid -o $m.wav \
    --sfz SalamanderV3/SalamanderGrandPianoV3.sfz \
    --samplerate 96000
  ffmpeg -i $m.wav -ar 48000 -sample_fmt s32 $m.flac
done
```

Outputs: `perf_ddrpt.flac` and `perf_hft.flac`. These are the two
candidates for the taste test.

### 6.3 Track B — OMR feasibility (~30 min, in parallel)

```bash
# Step 1: Audiveris on the PDF
audiveris -batch -export -output omr_out/ "Track Title.pdf"
# Outputs MusicXML; open in MuseScore for visual inspection

# Step 2: MusicXML → MIDI
python -c "
import music21
s = music21.converter.parse('omr_out/Track Title.xml')
s.write('midi', fp='reference.mid')
"
```

Then open `reference.mid` in MuseScore and visually compare to the
original PDF page-by-page. The Q2 answer is qualitative:

- **Clean** — note errors are rare (a handful of misread accidentals,
  no missing measures, no scrambled voice splits). Phase 1 is a go.
- **Repairable** — errors exist but follow patterns (e.g., always
  misreads the lower staff's voice 2). MuseScore cleanup is feasible
  per track but adds 10–20 min per track to Phase 2's manual budget.
- **Garbage** — voices are scrambled, measures are missing, the OMR
  output bears only loose resemblance to the score. Audiveris has
  failed on this typesetting; try Oemer (the deep-learning OMR) before
  declaring the hybrid path dead.

### 6.4 Listening (~30 min)

Real listening. Quiet room, the headphones or speakers you actually
listen on, no laptop fan in the picture. Protocol in §7.

---

## 7. Listening protocol

A/B comparison only works if it's structured. Otherwise the brain
defaults to "the louder one sounds better" and you'll convince yourself
of whichever you expected to prefer.

**Setup.**

- Same listening environment as your usual sessions.
- Match perceived loudness across files first. Sfizz output and the m4a
  will have different RMS — normalize with `ffmpeg-normalize` or by
  ear before comparing. Loudness differences swamp every other
  judgment.
- Use a player that can A/B without gaps (Audacity's multitrack mode,
  or just preload three browser tabs with the files).

**Listen to specific things, in this order:**

1. **A passage you know intimately.** 20–30 seconds. Listen to the m4a
   first to refresh the reference, then DDRPT, then hFT.
2. **Decay tails.** Pause the playback at the end of a long held chord.
   The release is where samplers most obviously sound like samplers and
   real recordings most obviously sound like real recordings.
3. **Fast passages.** A run, an arpeggio, an ornament. This is where
   transcription errors live. Listen for missing notes, smeared
   onsets, doubled notes.
4. **Pedaled sections.** Sustain that should bleed across measures.
   ByteDance / DDRPT model pedaling natively; hFT-Transformer's pedal
   handling is weaker. Notice if the resynthesis sounds drier than the
   original — usually means under-pedaling.
5. **The full track.** End to end, both renders. Note the moment you
   stop noticing it's a render and start hearing music. If that moment
   never comes, the answer to Q1 is no.

**Write down**, before looking at the other render's notes:

- Adjectives. ("Cleaner." "Plastic." "Lifeless." "Audiophile." "Wrong
  in bar 47.")
- Specific timestamps where something is broken.
- Which one you'd play if you only had one.

This is the actual data Phase 0 produces. The MIDI files are
intermediate; the listening notes are the deliverable.

---

## 8. Decision matrix

After listening, the joint outcome of Q1 and Q2 maps to a next-phase
decision:

| Q1 (taste) | Q2 (OMR) | What to do |
| --- | --- | --- |
| Clearly better than m4a | Clean | Proceed to Phase 1 with the winning transcriber. Hybrid path is on. |
| Clearly better than m4a | Repairable | Proceed to Phase 1, but budget +20 min/track for OMR cleanup in Phase 2. |
| Clearly better than m4a | Garbage | Try Oemer. If still bad, proceed to Phase 1 on the audio-only path; treat the result as `REMASTERING_PLAN.md` §4.1 territory and reconsider the project on its own terms. |
| About the same | any | Apply the §9.1 mitigations (Pianoteq trial, convolution reverb, release samples on). Re-listen. If still tied, kill the project — it's burning time for an outcome you're indifferent to. |
| Worse than m4a | any | Kill. The PDFs can't rescue an aesthetic you don't like. |
| DDRPT and hFT both broken in different ways | Clean | The track is hard for current transcribers. Try one more track before deciding — n=1 isn't enough to indict the pipeline if the OMR path is healthy. |

The "about the same" row is the one to be honest about. It's the
seductive failure mode — sunk cost makes everything sound a little
better the longer you've worked on it. If after the §9.1 mitigations
the answer isn't a clear preference, the answer is no.

---

## 9. Time budget

| Step | Active minutes |
| --- | --- |
| 5.   Pre-flight (Songscription) | 5 |
| 6.1  Setup, installs | 30 |
| 6.2  Audio-only path (DDRPT + hFT) | 45 |
| 6.3  OMR feasibility (parallel with 6.2) | 30 |
| 6.4 / 7.  Listening + notes | 30 |
| **Total** | **~2 h active**, ~3 h elapsed |

Setup is the long pole if Python or Audiveris aren't already on the
machine. Two hours active is the realistic floor on a clean machine;
expect three on a first-time run.

---

## 10. Non-goals for Phase 0

- **Don't write the orchestrator.** No `remaster.py`, no manifest, no
  resumability, no logging. All of that is Phase 1.
- **Don't run Nakamura alignment.** Reconciliation matters in Phase 1+
  but is overkill for Phase 0 — the audio-only render answers Q1 by
  itself, and visual inspection of the OMR output answers Q2.
- **Don't tune Salamander.** Default SFZ patch, default sample rate.
  Iterating on renderer settings before knowing whether resynthesis is
  even desirable is putting paint on a foundation that hasn't been
  poured.
- **Don't try multiple tracks unless the matrix says to.** One track is
  the budget. The temptation to "just try another one" is how a 3-hour
  decision gate turns into a weekend without producing a decision.
- **Don't apply the §9.1 mitigations preemptively.** The whole point
  of testing the unmitigated baseline first is that "it sounds great
  out of the box" and "it sounds great with reverb and Pianoteq" lead
  to very different total project costs.

---

## 11. Outputs to keep

Even though Phase 0 produces no scripts, keep the artifacts. They're
the regression baseline for Phase 1 — when the orchestrator is built,
its output on this same track should match Phase 0's MIDI within
floating-point noise.

```
phase0/
  audio.wav                 # decoded m4a
  perf_ddrpt.mid            # DDRPT transcription
  perf_hft.mid              # hFT-Transformer transcription
  perf_ddrpt.flac           # DDRPT render through Salamander
  perf_hft.flac             # hFT-Transformer render
  reference.mid             # OMR → music21 → MIDI
  omr_out/*.xml             # raw Audiveris MusicXML
  notes.md                  # listening notes, decision, rationale
```

The `notes.md` is the document that justifies (or ends) the project.
Write it the same evening, before bias drift sets in. If the decision
is to proceed, it goes into `docs/updates/` alongside the parent plan.
If the decision is to stop, it's still worth keeping — it's the
record of why, and the answer to "should we revisit this when
transcribers improve?" lives in those notes.
