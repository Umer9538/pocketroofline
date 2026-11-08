Raw run records land here, one JSON file per session, conforming to
../schema/run.schema.json. Files are never edited after commit: a correction is
a new run with a note, so the record stays auditable.

## Layout

- `*.json` in this directory: the run records, one per regime of a session, written by
  `harness/finalize.py` and checked by `harness/validate.py`. They are what `harness/report.py` reads.
- [`captures/`](captures/): the raw capture each session's records were finalized from, byte-for-byte as
  exported from the device, so the records can be regenerated and audited. The iPhone 15 Plus records came
  from `python3 harness/finalize.py "results/captures/pocketroofline-iPhone15,5-1791162656.json" --notes …`,
  with the notes text as it appears in each record. Captures are kept from 2026-10-05 on; earlier sessions'
  captures were not committed.
- [`bandwidth/`](bandwidth/): raw [Headroom](https://github.com/Umer9538/headroom) probe reports, byte-for-byte.
  Each runs Metal STREAM copy, scale, add and triad kernels over 128 MiB buffers. Together they give the
  measured bandwidth ceiling of METHODOLOGY §3: for each phone model and OS build, `harness/report.py` takes
  the median of the probes' verified GPU triad medians. Only probes taken under the session's conditions go
  here. Today that is four probes of the iPhone 15 Plus, taken 2026-10-05 01:05Z just before its run, at
  thermal state `fair` on battery. Three earlier pilot probes of that phone, taken while it was charging at
  thermal state `serious`, stay in the Headroom repository (`Calibration/runs/pilot/`) and are not used.
- `diagnostics/`: captures from the app's diagnostic run (`"kind": "diagnostic"`, `"matrixVersion":
  "diag-silo-first-1"`), byte-for-byte as exported. The folder appears with the first one. They are not
  matrix v1 runs: `harness/finalize.py` refuses them, `harness/report.py` and `harness/validate.py` never
  read them, and no figure on the results page comes from them. The run goes SILO first from a cool phone,
  then SISO, with a still screen, and records the decode rate of every 64-token window. It exists to
  explain the iPhone 15 Plus SILO step (README, caveat 3). Read one with
  `python3 harness/diagnose.py results/diagnostics/<file>.json`. It prints the window rates, the steps
  between repeats and the thermal transitions, then says which explanation the data are consistent with:
  a state change (H1), slow decode at long context (H2), or the app's live chart (H3). For full speed it
  reads, and never writes, that phone's matrix v1 SISO record here.
- `recovery/`: captures from the app's recovery test (`"kind": "recovery"`, `"matrixVersion":
  "recovery-ladder-1"`), byte-for-byte as exported. The folder appears with the first one. Like the
  diagnostics, they are not matrix v1 runs: `harness/finalize.py` refuses them, `harness/report.py`
  and `harness/validate.py` never read them, and no figure on the results page comes from them. The
  run heats the phone with SILO 128/1024 x 3, then rests 30, 60, 120 and 300 s with one SISO
  128/128 probe after each, on a still screen, with a 64-token window trace for every repeat. Start
  it on the phone with `xcrun devicectl device process launch --device <d> --terminate-existing
  com.umer9538.pocketroofline -- -PocketRooflineAutoRun recovery` (or the home screen's third
  button), and read it with `python3 harness/recovery.py results/recovery/<file>.json`. It prints
  the heat phase, each probe's decode as a share of the run's cold reference (the first window of
  the first heat repeat) and of that phone's matrix v1 SISO mean from a record here (read only),
  the thermal transitions, and a reading against thresholds declared at the top of the script. A
  capture with `plan.restScale` other than 1 came from the debug-only rest-scaling argument, is a
  pipeline check, and does not belong here.

## Screen during repeats

App records carry `uiDuringRepeats`. `"still"` means nothing on the phone's screen redrew while a
repeat measured; the app updated its chart only in the 3 s pause between repeats. `"live"` means the
run screen redrew a live decode chart every 16 tokens during each repeat, which competes with Metal
decode for the GPU: on the iPhone 15 Plus, SILO decode sat at about 25–32 tok/s that way and ran
47–56 tok/s on the diagnostic's still screen (a run that also put SILO first, on a cool phone, so the
chart is the leading suspect, not a proven cause). Every app capture made before the field existed was live,
including both iPhone 15 Plus captures in `captures/`; their records here predate the field and lack
it. The measurement protocol is the same either way.

## Errata

- **2026-10-04 — `model.config.attention` in the six matrix-v1 records says `MHA`.** The GGUF header of
  `tinyllama-1.1b-1t-openorca.Q4_0.gguf` (SHA-256 `bd07d1c5…`) reports 32 attention heads and 4 KV heads, so the
  model is GQA. The field is descriptive only: no figure on the page or in the posts is computed from it. Per the
  policy above the records are left as committed; this note is the correction.
