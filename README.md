# PocketRoofline

**Roofline analysis of LLM inference on smartphone-class silicon — with error
bars, and re-run on every OS and runtime update.**

[RooflineBench](https://arxiv.org/abs/2602.11506) (Bi et al., arXiv 2602.11506)
established a roofline-model framework for characterizing on-device LLM
inference, and evaluated it across five platforms: RTX 3090, RTX 3070 Ti
Laptop, Apple M1 Pro, Jetson Orin Nano Super, and Raspberry Pi 5.

**None of them is a phone.**

PocketRoofline extends that methodology to the device class the phrase
"on-device LLM" is usually about: shipping smartphones. It starts with an
iPhone 13 (A15 Bionic).

This repository opens with the protocol, not the results. Measurements land
here as they are taken, under the methodology fixed in
[`METHODOLOGY.md`](METHODOLOGY.md) before any number was collected.

---

## First result: sustained generation throttles the A15 by 24%

iPhone 13 (A15) · iOS 26.6.1 (23G83) · TinyLlama-1.1B Q4_0 · llama.cpp-Metal
(`95ef7fc`) · radios off, unplugged · 5 repeats per regime.

| Regime | Prefill tok/s | Decode tok/s | Thermal state |
|---|---|---|---|
| SISO (128 in / 128 out) | 504.0 | **42.80** (sd 0.37) | fair, stable |
| LISO (2048 in / 128 out) | 402.6 (−12.3%) | 42.42 | fair → **serious** |
| SILO (128 in / 1024 out) | 406.9 (−23.9%) | **40.53 → 30.93 (−23.7%)** | serious throughout |

Under sustained generation, decode falls **monotonically** across all five
repeats — Spearman rho = −1.00, a perfect rank trend. The same metric is stable
to 0.9% CV in SISO, so the decline is thermal, not measurement noise.

**Peak decode (42.80 tok/s) overstates sustained decode (30.93 tok/s) by 38%.**
Quoted phone inference numbers are peak numbers; on a phone that is roughly the
first minute. This is the behaviour a plugged-in desktop, laptop, Jetson or
Raspberry Pi cannot exhibit, and it is why the phone class needs its own
roofline data rather than an extrapolation from edge boards.

Honest limits on this session, recorded in every run file: the device began at
thermal state `fair` rather than `nominal` (the 10-minute cooldown of
METHODOLOGY §5 was not achieved), so these are **warm-start** figures; the LISO
repeat whose thermal state changed mid-run is flagged and excluded from
steady-state aggregates while retained in full; and SILO's mean is explicitly
**not** a steady-state figure, because the series is non-stationary by
construction — the throttling curve is the result, not its average.

Raw records: [`results/`](results/) — one JSON per regime, every repeat retained.
Generated page with charts and the full per-repeat tables:
**[umer9538.github.io/pocketroofline](https://umer9538.github.io/pocketroofline/)**

### The control: the same workload, plugged in

The identical model, quantisation, regime, backend and commit were run the same
day on a MacBook Pro (M1) — mains power, active cooling:

| Device | SISO decode | LISO decode | SILO decode (5 long generations) |
|---|---|---|---|
| iPhone 13 (A15) | 42.80 | 42.42 | **40.53 → 30.93** (rho −1.00) |
| MacBook Pro (M1) | 61.10 | 62.32 | **64.55 flat** (rho +0.10) |

The laptop shows no decline under the workload that costs the phone a quarter of
its throughput. Thermal behaviour, not raw silicon speed, is the thing phone
benchmarks have to capture — and it is precisely what a plugged-in laptop, a
Jetson or a Raspberry Pi cannot show.

---

## What this adds to the roofline picture

**1. Phone SoCs.** Operational intensity, attainable throughput, and the
empirical ridge point for A15-class silicon under llama.cpp-Metal, MLC, and
Core ML — measured on hardware that is thermally constrained, battery-powered,
and running a general-purpose OS that is not under our control.

**2. Confidence intervals on every number.** RooflineBench reports point
estimates; it does not report error bars, repeated-run variance, or confidence
intervals. Phone measurements need them more than desktop measurements do —
thermal state, background activity, and DVFS make a single run close to
meaningless. Every published figure is computed from the committed repeats by
[`harness/report.py`](harness/report.py) — mean, standard deviation, a bootstrap
95% interval on the mean, and a Spearman rank trend that separates a genuine
monotonic decline from scatter — and every underlying run is published alongside
it. Where a comparison between two devices or builds needs a certified verdict
rather than a descriptive interval, that is
[`unswayed`](https://github.com/Umer9538/unswayed)'s job and it is not wired in
yet.

**3. A longitudinal record.** The model x quantization x backend matrix is
pinned and versioned. It is re-run on every iOS point release and every
llama.cpp / MLC version bump, and regressions are gated by
[`vouch`](https://github.com/Umer9538/vouch). Snapshot benchmarks tell you what
a phone did once. This one is designed to tell you what changed underneath it —
a record that cannot be backfilled later.

## What this is not

- **Not a claim that phone inference is unmeasured.** Prieto & Abad (2025)
  evaluate SLMs across mobile CPUs, GPUs, and NPUs; Rajesh et al. (2025) compare
  MLX and MLC-LLM on Apple Silicon. What is missing is the *roofline / operational
  intensity* treatment applied to phone SoCs, with stated uncertainty, tracked
  over time. See [`PRIOR_ART.md`](PRIOR_ART.md).
- **Not a quality, safety, or capability benchmark.** Nothing here measures what
  a model says. This is performance characterization only.
- **Not a replacement for RooflineBench.** It is an extension of its
  methodology to a device class it did not cover, and the intent is to offer the
  phone data upstream.

## Honest limitations, stated up front

These are constraints of the measurement, not caveats to be buried:

- **Energy is a battery-drain proxy**, measured at the system level under a
  fixed protocol. It is not per-component power instrumentation, and it is not
  presented as such.
- **The ANE ceiling is empirical, not a roofline.** Apple does not publish the
  ANE's peak FLOPS or bandwidth. Core ML ANE numbers here are measured ceilings,
  labelled as measured ceilings.
- **One device is one device.** Results from a single iPhone 13 describe that
  unit, at that thermal state, on that OS build. Cross-device generalization
  waits for the community submission ledger (Phase 3).
- **The M1 anchor is a base M1, not the M1 Pro RooflineBench used.** Different
  memory bandwidth, different ridge point. The calibration chapter reports it as
  a different tier of the same family, not as an exact replication.

## Status

| Phase | Deliverable | State |
|---|---|---|
| 0 | Protocol, schema, priority stake | **done** |
| 1 | M1 anchor + A15 first numbers, one model across both | **done** (warm start; cold-start session owed) |
| 2 | Full matrix (models × quants × backends); bandwidth microbenchmark; preprint | not started |
| 3 | Community submission ledger | not started |

Published so far: one model (TinyLlama-1.1B Q4_0), one backend
(llama.cpp-Metal), two devices, three regimes, five repeats each — the A15
session warm-start. Not yet measured: other models and quantisations, MLC and
Core ML backends, the STREAM-style bandwidth ceiling that fixes the ridge point,
energy per token, and any device beyond these two. This section is the current
truth and will be kept current.

## Layout

```
METHODOLOGY.md      measurement protocol, fixed before data collection
PRIOR_ART.md        what exists already, and what this adds
schema/             result file schema; every published number conforms
harness/            build + run instructions per backend
results/            raw runs, one file per session, never edited after commit
```

## Citing the work this builds on

```bibtex
@article{bi2026rooflinebench,
  title  = {RooflineBench: A Benchmarking Framework for On-Device LLMs via Roofline Analysis},
  author = {Bi, Zhen and Chen, Xueshu and Sun, Luoyang and Yao, Yuhang and
            Shen, Qing and Lou, Jungang and Deng, Cheng},
  journal = {arXiv preprint arXiv:2602.11506},
  year   = {2026},
  url    = {https://arxiv.org/abs/2602.11506}
}
```

Their implementation: [banbu-ai/roofline_bench](https://github.com/banbu-ai/roofline_bench).

MIT licensed. Maintained by Muhammad Umer.
