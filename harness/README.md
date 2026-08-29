# Harness

Build and run instructions per backend. Each backend must emit a record
conforming to [`../schema/run.schema.json`](../schema/run.schema.json).

**Nothing in here has produced a published number yet.** Steps are marked with
what has actually been executed, so this file never overstates the state of the
work.

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

Status: **not yet executed.**

## Calibration anchor: llama.cpp-Metal on Apple M1

Runs on the development machine and needs no app bundle — this is where the
schema and the statistics get exercised first, before the device work.

Note the machine here is a **base M1**, not the M1 Pro used by RooflineBench.
Different memory bandwidth, therefore a different empirical ridge point. This
is a same-family lower tier, reported as such — never as a reproduction of
their M1 Pro figures.

Requires: `cmake`, a llama.cpp checkout at a pinned tag, and GGUF weights whose
SHA-256 is recorded in the run record.

Status: **not yet executed.**

## Bandwidth microbenchmark

STREAM-style Metal kernels (copy / scale / add / triad) over buffers larger than
last-level cache, establishing the empirical sustained-bandwidth ceiling used to
place the ridge point (METHODOLOGY.md §3).

Status: **not yet written.**
