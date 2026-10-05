# Harness

Build and run instructions per backend. Each backend must emit a record
conforming to [`../schema/run.schema.json`](../schema/run.schema.json).

Each section says what has actually been executed and when, so this file
never overstates the state of the work.

## Phase 0 target: llama.cpp-Metal on iPhone 13

The A15 has no command-line access, so `llama-bench` cannot simply be run on
device. The path is llama.cpp's SwiftUI example target, modified to run the
fixed regimes from `matrix/v1.json` headlessly and write a schema-conforming
JSON to the app container.

Steps:

1. Clone llama.cpp at a pinned tag; record the tag and commit SHA.
2. Build `examples/llama.swiftui` for iOS, Metal enabled.
3. Replace the interactive loop with the regime runner: for each regime, run
   `repeatsMinimum` repeats, recording prefill tok/s, decode tok/s, TTFT, peak
   resident memory, and `ProcessInfo.thermalState` at start and end of each repeat.
4. Enforce the cooldown from METHODOLOGY.md §5 between repeats.
5. Write the run record; export via the Files app or Xcode container download.

Status: **executed 2026-09-03** on an iPhone 13 (iOS 26.6.1, 23G83) with the
modified demo in [`ios-patch/`](ios-patch/), finalized by `finalize.py` into the
three `results/iphone13-*` records. Deviation: the session was a warm start
(thermal state `fair`), and the repeats were ~3 s apart rather than separated
by the §5 cooldown; both are stated in the records' notes.

Since 2026-10-05 the same regimes also run in the standalone app in
[`../app/`](../app/), first on an iPhone 15 Plus (A16). Its captures need no
manual fill-in and are kept in `results/captures/`.

## Calibration anchor: llama.cpp-Metal on Apple M1

Runs on the development machine and needs no app bundle — this is where the
schema and the statistics get exercised first, before the device work.

Note the machine here is a **base M1**, not the M1 Pro used by RooflineBench.
Different memory bandwidth, therefore a different empirical ridge point. This
is a same-family lower tier, reported as such — never as a reproduction of
their M1 Pro figures.

Requires: `cmake`, a llama.cpp checkout at a pinned tag, and GGUF weights whose
SHA-256 is recorded in the run record.

Status: **executed 2026-09-03** with `llama-bench` at the same commit and on the
same model, into the three `results/m1-*` records. This is a different timing
harness from the phone's, which the records' notes say.

## Bandwidth microbenchmark

STREAM-style Metal kernels (copy / scale / add / triad) over buffers larger than
last-level cache, establishing the empirical sustained-bandwidth ceiling used to
place the ridge point (METHODOLOGY.md §3).

Status: **written as a separate package,
[Headroom](https://github.com/Umer9538/headroom)** (Metal copy / scale / add /
triad plus a CPU triad). Executed on the iPhone 15 Plus (A16) on 2026-10-05:
four probe reports in `results/bandwidth/`, median GPU triad 45.3 GB/s. **Not
yet executed on the A15**, so the iPhone 13's roofline placement still rests on
published peak figures.
