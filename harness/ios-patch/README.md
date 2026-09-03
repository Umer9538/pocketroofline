# iOS harness patch — llama.cpp SwiftUI regime runner

Reference copies of the three files modified in llama.cpp's
`examples/llama.swiftui` to turn the demo app into a PocketRoofline regime
runner. All three already belong to the Xcode target, so applying them needs
**no project-file edits** — replace the originals and rebuild.

Built against llama.cpp commit `95ef7fc16054e63b427a3ef00188e055ef7586d8`.

## What each file adds

- **LibLlama.swift** — `prBenchOnce(promptTokens:generateTokens:)` on
  `LlamaContext`: one measured repeat, prefill and decode timed separately with
  synthetic tokens (pure-compute timing, matching llama-bench), returning
  prefill tok/s, decode tok/s, and TTFT ms. Plus `prModelParams()` /
  `prModelSizeBytes()`.
- **LlamaState.swift** — `pocketRoofline(modelId:quant:)`: runs matrix v1
  regimes (SISO 128/128, LISO 2048/128, SILO 128/1024) × 5 repeats with one
  unrecorded warmup, capturing `ProcessInfo.thermalState` at the start and end
  of every repeat, resident memory, and device/OS metadata via `UIDevice` +
  `uname`. Emits a capture JSON to the app's Documents directory and copies it
  to the clipboard. Fields it cannot know on-device (`soc`, `ramGB`, OS build,
  backend commit, weights SHA-256) are written as `FILL-IN` and completed on
  the Mac by `finalize.py`.
- **ContentView.swift** — a "Roofline" button that calls it. Set `modelId` /
  `quant` in `pocketRoofline()` to match the loaded model before running.

## Run protocol (METHODOLOGY §5–6)

1. iPhone in **airplane mode**, screen at fixed brightness, **unplugged**,
   battery 40–80%, no other foreground apps.
2. Cool to ambient (thermal state nominal) before starting; 10 min between
   full sessions.
3. Launch the app, download/load the target model, tap **Roofline**.
4. Retrieve the JSON: clipboard (paste to yourself), the Files app, or Xcode →
   Devices & Simulators → the app → Download Container.
5. On the Mac, run `harness/finalize.py <capture.json>` to fill the `FILL-IN`
   fields and validate against `schema/run.schema.json`, then commit to
   `results/`.
