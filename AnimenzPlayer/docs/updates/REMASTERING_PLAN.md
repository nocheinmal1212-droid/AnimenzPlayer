# Remastering Plan — MIDI Re-synthesis of the Animenz Library

*Non-wave feature. Stylistically matches `docs/updates/WAVE3_PLAN.md`.*

---

## Table of contents

1. [Goal](#1-goal)
2. [What we have](#2-what-we-have)
3. [Why the PDFs change the shape of the problem](#3-why-the-pdfs-change-the-shape-of-the-problem)
4. [Approaches considered](#4-approaches-considered)
5. [Tooling decisions](#5-tooling-decisions)
6. [Per-track pipeline](#6-per-track-pipeline)
7. [Phases](#7-phases)
8. [App integration (Phase 3 detail)](#8-app-integration-phase-3-detail)
9. [Risks, open questions, kill criteria](#9-risks-open-questions-kill-criteria)
10. [Time budget](#10-time-budget)
11. [Scaffolding to commit first](#11-scaffolding-to-commit-first)
12. [Deliberate non-goals](#12-deliberate-non-goals)

---

## 1. Goal

Produce a parallel library of high-fidelity renditions of every track we
currently have as m4a, by (a) extracting a MIDI performance from the audio,
(b) correcting that MIDI against the published sheet music, and
(c) rendering it through a sampled or modeled piano. The output coexists
with the m4a library rather than replacing it, so the taste question —
"do I prefer the original recording or the resynthesis?" — can be answered
per track, per listening session, and revised later.

This is a **non-wave feature** per `BRANCHING.md` §6. It branches from
`main`, merges back to `main`, does not block Wave 4, and does not touch
`PlayerBarView` or `ContentView`'s layout. The Swift-side integration is
small and additive: a new `AudioSource` concept on `Track`, a variant-aware
`LibraryStore`, and one `@AppStorage` key. Everything else is offline
tooling that produces files the existing app already knows how to play
(FLAC is in `LibraryStore.audioExtensions`).

---

## 2. What we have

- ~165 audio tracks in `AnimenzPlayer/Music/`, format `m4a`, filenames
  following yt-dlp's `%(playlist_index)03d - %(title)s [%(id)s].%(ext)s`
  template.
- Sidecar JPEG thumbnails for each track.
- Sheet music for the Animenz arrangements as PDF (one PDF per
  arrangement — 1:1 with tracks).
- An app that already scans a flat folder, already supports FLAC, and is
  already tolerant of the library being modified between launches (Wave 3's
  scope-snapshot filter handles stale URLs gracefully).

Not having to change any of that is most of why this is a tractable side
project rather than a Wave 5.

---

## 3. Why the PDFs change the shape of the problem

The idea as originally stated is a two-step pipeline: audio → MIDI →
audio. In that shape, the quality ceiling is bounded by the transcriber.
ByteDance's model and Transkun are strong, but they still miss fast
ornaments, hallucinate notes on dense chords, and drift on rubato — the
exact phenomena Animenz's arrangements are full of.

The PDFs turn it into a three-step pipeline with a validation rail:

```
┌───────────────┐   transcribe    ┌──────────────────┐
│  m4a audio    ├────────────────►│ performance MIDI │──┐
└───────────────┘                 │ (notes + timing) │  │
                                  └──────────────────┘  │
                                                        ├──► reconciled ──► render
┌───────────────┐      OMR        ┌──────────────────┐  │
│ PDF sheets    ├────────────────►│  reference MIDI  │──┘
└───────────────┘                 │ (notes + rhythm) │
                                  └──────────────────┘
```

The reference MIDI (from OMR) contributes the correct **notes** — which
chords, which voicings, which passing tones. The performance MIDI (from
audio transcription) contributes the correct **timing and dynamics** —
rubato, pedaling, velocity contour. Reconciling them beats either input
alone because the two failure modes are largely independent: OMR fails on
layout and rhythm complexity, audio transcription fails on pitch recall
and ornament resolution, and they rarely fail on the same bar.

This isn't hypothetical. Nakamura et al.'s symbolic music alignment work
(ISMIR 2017 and follow-ups) is the algorithm that makes the reconciliation
rigorous; there are reference Python implementations; and MuseScore 4 has
an audio-to-score alignment feature built on similar ideas. The step is
routine in the MIR community even if it's novel in a consumer pipeline.

---

## 4. Approaches considered

### 4.1 Audio-only transcription (the original idea)

- **Pros.** Simplest pipeline. Works on tracks without PDFs. Preserves
  the performance nuance within the transcriber's resolution.
- **Cons.** Transcription errors are final. Fast passages degrade
  audibly. No way to distinguish "the transcriber missed a grace note"
  from "Animenz added a grace note".

### 4.2 OMR-only from PDFs

- **Pros.** Notes are nearly exact. Deterministic — no ML mood swings.
- **Cons.** Loses the performance entirely. Every track sounds like a
  quantized MIDI file, because that's literally what it is. This
  produces a version of the score a typesetting program could have
  produced from day one. Not "audiophile Animenz"; "Finale playing the
  sheet music."

### 4.3 Hybrid (recommended)

Higher cost per track, but the only one of the three that credibly
claims to be *Animenz, cleaner* rather than *a different artistic object*.
Every section below assumes the hybrid path and flags where degrading
gracefully to 4.1 is the right fallback.

---

## 5. Tooling decisions

### 5.1 Transcriber — ByteDance first, Transkun fallback

`piano_transcription_inference` (the packaged ByteDance model) is the
first-choice transcriber: stable PyPI package, models pedaling natively,
well-understood failure modes. Transkun is marginally stronger on some
benchmarks but the tooling is less settled. Both take a wav in and
produce a MIDI out, so swapping is a one-line change. Plan is to use
ByteDance throughout and switch to Transkun on specific tracks where the
reconciliation pass flags low confidence.

```
pip install piano_transcription_inference
# ~150 MB model weights auto-download on first run, cached
```

Runs on CUDA GPUs or Apple Silicon via PyTorch MPS. MPS is slower but
fine for unattended overnight runs.

### 5.2 OMR — Audiveris first, Oemer fallback

Audiveris is the established open-source OMR, outputs MusicXML,
round-trips through `music21` into MIDI. Not magic — dense piano scores
produce errors, especially on ledger lines and voice splits — but for
typeset PDFs (which Animenz's are) it's usable. Realistic estimate: 70–85 %
clean pass-through; 15–30 % needs MuseScore cleanup.

Oemer is a deep-learning OMR worth trying on tracks where Audiveris
produces garbage. Narrower coverage but occasionally wins on layout
recovery.

The PDF→MIDI branch is the most operationally fragile step in the
pipeline. Budget for manual intervention on a meaningful fraction of
the library. This is the single most likely reason to kill the project
mid-flight — see §9.

### 5.3 Alignment — symbolic_music_alignment (Nakamura)

Nakamura's alignment code (available as a Python package and a reference
C++ implementation) performs the reconciliation. Given reference MIDI
and performance MIDI it produces an aligned MIDI where:

- Notes in the reference but missed in the performance are inserted
  with interpolated timing.
- Spurious notes in the performance that aren't in the reference are
  dropped, with a configurable confidence threshold so Animenz's
  genuine additions aren't killed.
- Velocities and precise onsets come from the performance.
- Pedaling comes from the performance.

A per-bar alignment confidence score comes out of this step and drives
both automated fallback (below a threshold, don't reconcile; use the
performance MIDI as-is) and manual triage.

### 5.4 Renderer — Salamander V3 via Sfizz, Pianoteq as upgrade

**Salamander Grand Piano V3.** The standard free SFZ piano: Yamaha C5,
16 velocity layers, CC-BY-SA. The other free options (Sonatina,
FluidSynth's default SF2) are all noticeably worse.

**Sfizz.** Headless SFZ renderer. CLI, cross-platform, wav/flac out.

```
brew install sfizz
sfizz_render -i in.mid -o out.wav \
  --sfz "/path/to/Salamander/SalamanderGrandPianoV3.sfz" \
  --samplerate 96000 --blocksize 2048
```

**Pianoteq.** Commercial (~€300 Standard), physical modeling rather
than sampled. Tiny footprint (~50 MB), more natural note-to-note
behavior (sympathetic resonance, true release, configurable hammer
hardness), CLI rendering supported. The upgrade if the Salamander
output comes back too "samples-y" in Phase 0.

The pipeline is renderer-agnostic — the real output is the reconciled
MIDI; the renderer is last-mile.

### 5.5 File formats

- **Intermediate wav**, 96 kHz/24-bit, from sfizz. Not kept.
- **Final FLAC**, 48 kHz/24-bit. Lossless, ~30 MB per 4-min track,
  universally decoded. 96 kHz masters would be marketing; humans can't
  tell and the app doesn't benefit.
- **Kept alongside the FLAC, per track:**
  - `.mid` — the reconciled MIDI. Enables re-rendering with any future
    renderer without redoing steps 1–4, and enables the roadmap's MIDI
    export feature "for exporting the piano covers' transcribed notes."
  - `.xml` — the MusicXML from OMR. Small cost, real future value.
  - `.transcription.json` — per-track metadata: model versions, tool
    versions, per-bar alignment confidence, whether manual edits were
    applied, which fallback branch ran.

Storage budget:

| Asset                       | Approx size |
| --------------------------- | ----------- |
| m4a library (existing)      | ~1.2 GB     |
| FLAC remaster               | ~5 GB       |
| MIDI + MusicXML + manifests | ~50 MB      |
| **Total**                   | **~6–7 GB** |

Fine on a Mac; potentially notable on iOS if both libraries ship
in-bundle. Mitigation in §9.

---

## 6. Per-track pipeline

Deterministic from inputs:

```
Inputs
  audio_in : AnimenzPlayer/Music/NNN - Title [id].m4a
  pdf_in   : sheets/NNN - Title.pdf

Step 1 : Decode to wav, 44.1 kHz, mono
  ffmpeg -i audio_in -ac 1 -ar 44100 tmp/audio.wav

Step 2 : Audio transcription
  piano_transcription_inference --input tmp/audio.wav
                                --output tmp/performance.mid

Step 3 : OMR
  audiveris -batch -export tmp/ pdf_in
  python scripts/musicxml_to_midi.py tmp/*.xml tmp/reference.mid

Step 4 : Alignment
  python scripts/align.py \
      --reference   tmp/reference.mid \
      --performance tmp/performance.mid \
      --output      out/NNN.mid \
      --confidence-log out/NNN.transcription.json \
      --no-reconcile-below-confidence 0.6

Step 5 : Render
  sfizz_render -i out/NNN.mid -o tmp/rendered.wav \
      --sfz SalamanderV3/SalamanderGrandPianoV3.sfz \
      --samplerate 96000

Step 6 : Encode
  ffmpeg -i tmp/rendered.wav -ar 48000 -sample_fmt s32 \
      "remastered/NNN - Title [id].flac"

Step 7 : Copy sidecar thumbnail
  cp "AnimenzPlayer/Music/NNN - Title [id].jpg" \
     "remastered/NNN - Title [id].jpg"
```

Each step is a separate script. A driver (`scripts/remaster.py`)
orchestrates them with per-track resumability and a manifest that
records which steps have completed for each track, so partial runs
don't redo work. Steps 2 and 5 are GPU-accelerated when available.

Step 4's `--no-reconcile-below-confidence` is load-bearing: when the OMR
and audio transcription disagree wildly (usually because the PDF is a
different revision of the arrangement than what Animenz recorded), the
alignment pass makes things worse instead of better. Under the threshold,
the pipeline falls back to Approach 4.1 and records the fallback in the
manifest.

---

## 7. Phases

### Phase 0: Decision gate — *no code written*
*Time: one evening. 2–3 active hours.*

Pick **one** track you know well — something mid-difficulty with clear
performance character. Run the pipeline manually, mostly in GUI tools.
Listen on your usual setup. Answer:

- Does the result sound meaningfully better than the m4a?
- Does it still feel like *Animenz* playing, or like a different pianist
  who played the same notes?
- What's broken, and whose fault is it — transcriber, OMR, or renderer?

This is the taste-question checkpoint. If the answer is "worse in ways I
care about," stop. A weekend of automation work on a pipeline whose
output you don't like is a weekend wasted. If the answer is "cleaner but
sterile," try Pianoteq before giving up.

### Phase 1: Pilot — *3 tracks, scripted*
*Time: one weekend. ~10 active hours.*

Automate the pipeline end-to-end on three tracks spanning the difficulty
distribution:

- Sparse/slow (a ballad arrangement).
- Medium (a typical OP arrangement).
- Dense/fast (something with rapid ornaments).

Exit criteria:

- Per-stage artifacts inspectable at every step.
- Alignment confidence JSON correlates with subjective quality.
- Pipeline is deterministic: rerunning produces bit-identical outputs
  from identical inputs. (This matters for resumability and for giving
  the manifest any authority.)

### Phase 2: Batch — *all 165 tracks*
*Time: overnight compute, ~1 week wall-clock for manual triage.*
*Active: 8–15 hours, mostly MuseScore cleanup.*

Run the pipeline unattended. Expect roughly:

- ~75 % of tracks end-to-end with no input.
- ~15 % flag low alignment confidence — manual review, usually an OMR
  fix in MuseScore, then rerun from step 4.
- ~5–10 % require more serious intervention (missing page in PDF,
  complex voice split Audiveris can't parse, transcription error the
  PDF doesn't fix because OMR failed too).

Don't try to fix everything on the first pass. Ship the 90 % that works
and circle back. The manifest is the triage tool.

### Phase 3: App integration
*Time: 2–3 evenings. 4–6 active hours.*

Branch: `feature/audio-source`, off `main`, per `BRANCHING.md` §6. See §8
below for surface detail.

---

## 8. App integration (Phase 3 detail)

Minimum additive surface. Everything below is appended, not restructured —
the chokepoint rules from `BRANCHING.md` §5 apply to `PlayerViewModel` and
`PersistenceStore.State` here just as they did to Wave 3.

### 8.1 `Track` gets an `AudioSource`

New file, `Models/AudioSource.swift`:

```swift
enum AudioSource: Hashable {
    case original(URL)   // the m4a from yt-dlp
    case remaster(URL)   // the FLAC from the pipeline
}
```

`Track` gains a `sources: [AudioSource]`. `Track.url` becomes a computed
property that picks based on a preference (§8.3). Identity (`id`,
`Equatable`, `Hashable`) still keys off the original m4a URL so favorites,
recents, and the scope snapshots from Wave 3 all survive unchanged.

### 8.2 `LibraryStore` coalesces variants

Currently `LibraryStore` emits one `Track` per audio file. It needs to
emit one `Track` per `(index, title, videoid)` tuple, with the audio
sources collected into `sources`. The change is localized to
`discoverTracks()`: group by the stripped basename before constructing
`Track`s.

This is a behavior change visible from `PlayerViewModelTests` — any test
that seeded the library with multiple files per logical track implicitly
needs updating, though in practice the existing tests only use one file
per track, so the surface is small. Add a new test file
`LibraryStoreTests.swift` with the coalescing cases explicit.

### 8.3 Preference — one `@AppStorage` key, no UI yet

```swift
@AppStorage("preferredAudioSource") var preferredAudioSource: String = "original"
```

`Track.url` consults it:

```swift
var url: URL {
    let prefer: (AudioSource) -> Bool = ...  // read from AppStorage
    return sources.first(where: prefer)?.underlyingURL
        ?? sources.first!.underlyingURL
}
```

No settings screen ships with this branch. One `@AppStorage` line is the
entire user-control surface for v1 — flipping it requires setting the key
manually (or via the Wave 4 settings surface, when it exists). This is
deliberate: a settings UI is its own thing, and shipping the mechanism
decoupled from the UI keeps this feature branch small enough to review.

### 8.4 Persistence — appended, per the chokepoint rule

`PersistenceStore.State` gains an optional per-track override map:

```swift
struct State: Codable {
    // ... existing fields, unchanged ...
    var audioSourceOverrides: [URL: String]? = nil   // Remaster-era: v4
}
```

Append-only, nil-safe, backward-compatible — same rules as Wave 3's
state additions. The map is optional *and* the per-track values are
optional; absence means "use the global preference."

### 8.5 Non-goals for this branch

- No settings UI.
- No per-track A/B toggle in the player bar. That's Wave-4-adjacent
  and would contend with Wave 4's planned player bar rewrite. Wait for
  Wave 4.
- No streaming / on-demand rendering. Remastered files ship as static
  FLACs alongside the m4as.

---

## 9. Risks, open questions, kill criteria

### 9.1 "It sounds sterile"

The most likely subjective outcome. Mitigations, in order of cheapness:

1. Pianoteq instead of Salamander. Biggest single quality jump available.
2. A light convolution reverb between Steps 5 and 6. Voxengo's free IR
   library has plenty of "small room" and "recital hall" options that
   get closer to the acoustic Animenz recorded in.
3. Render with Salamander's built-in release samples enabled (they're
   off by default in some SFZ patches for CPU reasons; turning them on
   recovers the resonance tail that makes piano sound like piano).

If Phase 0 with all three applied still sounds sterile, the taste
question has answered itself and the project should stop.

### 9.2 PDF and audio are different arrangement revisions

Animenz sometimes publishes multiple revisions. If the PDF doesn't match
the audio, alignment confidence craters and reconciliation makes things
worse. Mitigation: the confidence threshold in Step 4 falls back to
audio-only for that track and records the fallback.

### 9.3 Licensing

- Salamander V3 is CC-BY-SA. Rendered output is distributable with
  attribution. Add Salamander's credit to the app's Acknowledgements.
- Pianoteq output is freely distributable per their license.
- OMR of PDFs you own is fine; redistributing the PDFs is a separate
  question and outside scope.
- The reconciled MIDI is a derivative of Animenz's arrangement. Personal
  use is fine. The README already scopes the library as per-developer,
  so distribution never comes up.

### 9.4 Double storage on iOS

6–7 GB is fine on a Mac; on iOS it's a bundle-size concern if both
libraries ship in-app. Options for later: (a) ship only m4a in-bundle,
fetch remaster from iCloud on demand; (b) ship remaster only and drop
m4a from the iOS build; (c) accept the size. Not a v1 blocker — the Mac
build is the immediate target.

### 9.5 Tracks without published sheets

Live improvisations, older tracks, collaborations may lack PDFs. The
pipeline degrades to audio-only transcription (Approach 4.1) for those.
Lower quality ceiling but still usable; manifest records which branch
ran so they're candidates for reprocessing if sheets appear later.

### 9.6 Kill criteria

Stop the project if any of:

- Phase 0 pilot doesn't clearly beat the m4a, even after §9.1.
- Phase 1 produces only 1-of-3 pilot tracks you'd prefer.
- Phase 2 manifest shows >40 % of tracks needing manual OMR cleanup —
  means Audiveris can't handle Animenz's typography, the hybrid path
  collapses back to audio-only, and you should evaluate 4.1 on its own
  terms rather than through this pipeline.
- Storage cost lands at >2× projection with no commensurate quality win.

---

## 10. Time budget

| Phase                              | Elapsed     | Active hours |
| ---------------------------------- | ----------- | ------------ |
| Phase 0: one-track taste check     | 1 evening   | 2–3          |
| Phase 1: pilot, 3 tracks           | 1 weekend   | ~10          |
| Phase 2: batch + manual triage     | 1–2 weeks   | 8–15         |
| Phase 3: app integration           | 2–3 evenings| 4–6          |
| **Totals**                         | **~3 weeks**| **~25–35**   |

The "165 tracks in a weekend" framing in the original idea is plausible
only if you skip Phase 0, which is exactly the phase you shouldn't skip.
Phase 0 is the cheapest information you'll get about whether this is
worth doing.

---

## 11. Scaffolding to commit first

Before any batch runs:

```
scripts/                       # not in any Xcode target
  remaster.py                  # orchestrator
  transcribe.py                # audio → performance MIDI
  omr.py                       # PDF → reference MIDI
  align.py                     # reconciliation
  render.py                    # MIDI → FLAC
  manifest.py                  # per-track state
  requirements.txt             # pinned Python deps
sheets/                        # user-provided PDFs, gitignored
remastered/                    # pipeline outputs, gitignored
```

Plus additions to `.gitignore` for `sheets/`, `remastered/`,
`scripts/tmp/`. Plus a `REMASTER.md` at repo root describing setup:
Python version, pip install, where to put Salamander V3, where
Audiveris needs to be on PATH, how to resume from a partial batch.

No Swift code changes in this step — Swift-side work is Phase 3, a
separate branch.

---

## 12. Deliberate non-goals

- **Ship the PDFs.** User's working copy.
- **Train or fine-tune a model.** Off-the-shelf checkpoints throughout.
- **Dynamic/adaptive rendering** (mixing the m4a and the render together).
  Product question for later, not a pipeline question now.
- **Auto-delete m4a files.** Both libraries coexist indefinitely. The
  taste question is ongoing, not a commit.
- **Build an A/B comparison UI.** Wave-4-adjacent; waits for Wave 4.
- **Solve every track.** Ship the 90 % that works cleanly; triage the
  rest in follow-up work.
