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
iPhone 13 (A15 Bionic); an iPhone 15 Plus (A16 Bionic) is the second phone.

**Write-up:** [Your phone runs a language model at 42 tokens per second — for about a minute](https://medium.com/@muhammadumer9538/your-phone-runs-a-language-model-at-42-tokens-per-second-for-about-a-minute-2907d93282a7) (Medium)

This repository opens with the protocol, not the results. Measurements land
here as they are taken, under the methodology fixed in
[`METHODOLOGY.md`](METHODOLOGY.md) before any number was collected.

### Related work, and what this adds

- [RooflineBench](https://arxiv.org/abs/2602.11506) (Bi et al., 2026): the roofline framework this project
  extends. Its platform set contains no phone.
- [arXiv:2603.23640](https://arxiv.org/abs/2603.23640) (March 2026): sustained-load measurements on a Galaxy
  S24 Ultra and an iPhone 16 Pro (MLX, Qwen 2.5 1.5B). The iPhone fell from 40.5 to 23.7 tok/s over 20
  runs, with `ProcessInfo.thermalState` logged per run. So the thermal collapse itself is independently
  documented: it is not unique to this project, and that corroboration is welcome.
- Community leaderboards such as [TokForge](https://tokforge.ai/leaderboard/) and
  [DeviceMark](https://huggingface.co/datasets/devicemark/results) collect decode speeds from real phones,
  measured as short bursts (best-of-three or median-of-three passes).

What PocketRoofline adds is the **roofline placement** on phone silicon (achieved memory bandwidth against the
device ceiling), a **mains-powered control** run with the identical workload, a **protocol fixed before any
measurement** with every repeat committed as JSON, and a **longitudinal record** re-run on every OS build.

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

## Second phone: iPhone 15 Plus (A16): three sessions, one unexplained SILO step

iPhone 15 Plus (A16 Bionic, 6 GB) · TinyLlama-1.1B Q4_0 · llama.cpp-Metal (`95ef7fc`) · PocketRoofline
app 1.0 (1) · airplane mode, unplugged · 5 repeats per regime. Three sessions, each kept separate, never
pooled. Decode tok/s:

| Session | SISO | LISO | SILO, each repeat | Thermal during SILO |
|---|---|---|---|---|
| 2026-10-05 · iOS 27.0 (24A437) · warm start · live chart | **65.16** (sd 0.52) | 63.91 → 59.17 | 29.69, 30.89, 31.73, 28.00, 27.16 | serious |
| 2026-11-08 · iOS 27.0.1 (24A446) · cold start · live chart | 66.00 → 58.50 (mean 62.24) | 58.79 → 57.12 | 42.01, 24.94, 25.65, 25.78, 25.64 | nominal → fair |
| 2026-11-08 · iOS 27.0.1 (24A446) · cold start · still screen | **57.25** (sd 0.17) | 56.95 → 55.88 | 51.19, 34.61, 33.19, 32.42, 30.05 | fair → serious |

"Live chart" means the app redrew a decode chart during every repeat; "still screen" means nothing
redrew until the pause between repeats (`uiDuringRepeats` in each record).

**Roofline placement against a measured ceiling.** In the 2026-10-05 session, SISO decode reads weights
at 41.4 GB/s, which is **91% of this phone's measured ceiling** of 45.3 GB/s. The ceiling is the median of
four [Headroom](https://github.com/Umer9538/headroom) probes (a Metal STREAM triad over three 128 MiB
buffers) taken on the same phone and OS build just before that run, at thermal state `fair`, on battery.
It is the measured ceiling METHODOLOGY §3 asks for, and the A16 is the first chip here to have one; the
A15's placement still rests on published figures that disagree. The ceiling was not re-probed on 24A446,
so the November sessions get achieved bandwidth only. No published A16 figure is used.

**The SILO step: what is known.**

- **It recurs.** In all three sessions, on two OS builds, SILO decode ends up far below LISO: the last
  LISO repeat ran 59.17, 57.12 and 55.88 tok/s, and the SILO repeats after the first ran 27–32, 25–26
  and 30–35 tok/s.
- **It happens with a still screen**, so the live chart is not its main cause. After the step SILO ran
  30.05–34.61 tok/s with the screen still and 24.94–25.78 in the cold live-chart session. That is one run
  of each, so the gap is not read as an effect of the chart.
- **It arrives after roughly 70–100 s of continuous load, in every ordering:** during the first SILO
  repeat (about 72–97 s in, estimated from repeat timings) in both cold sessions, and at 81 s in a
  SILO-first diagnostic run. In the cold live-chart session iOS reported only `fair`, never `serious`.
- **Decode bounces back after a pause.** In the diagnostic, decode fell about 10% inside each 1024-token
  repeat and started fast again after the 3 s pause; once iOS reported `serious` it sank to about 40 tok/s
  late in a repeat (lowest 64-token windows 42.0 and 38.8), yet the repeats after those began at 57.7
  and 57.4. The benchmark
  sessions record no per-window trace, so whether they bounce back too cannot be seen.
- **The cause is still unexplained.** The next experiment is the app's recovery test, which heats the
  phone and times how long decode takes to come back.

**Warm start (2026-10-05 session only).** The phone was at thermal state `fair` when that run began; the
10-minute cooldown of METHODOLOGY §5 was not achieved, the same deviation as the iPhone 13 session.

No peak-to-sustained percentage is quoted for this phone, and its SILO numbers are not a
sustained-throughput figure. Repeats whose thermal state changed mid-run are flagged and left out of
the aggregates (METHODOLOGY §5). Raw captures: [`results/captures/`](results/captures/); diagnostic:
[`results/diagnostics/`](results/diagnostics/); probe reports: [`results/bandwidth/`](results/bandwidth/).

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
- **One device is one device.** Results from one iPhone 13 and one iPhone 15
  Plus describe those two units, each at its own thermal state, on its own OS
  build. Two phones are not a trend. Cross-device generalization waits for the
  community submission ledger (Phase 3).
- **The M1 anchor is a base M1, not the M1 Pro RooflineBench used.** Different
  memory bandwidth, different ridge point. The calibration chapter reports it as
  a different tier of the same family, not as an exact replication.

## Run it on your phone

The [`app/`](app/) folder is a standalone iOS app that runs the same fixed
benchmark (TinyLlama-1.1B Q4_0, SISO/LISO/SILO, five repeats each) on your own
iPhone, shows decode speed live as the phone heats up, and gives you a result
card. Build it from source with Xcode — see [`app/README.md`](app/README.md).

**TestFlight: coming soon** (no public link yet).

To add your phone to the benchmark, tap **Submit** at the end of a run. It opens a
pre-filled [device capture issue](https://github.com/Umer9538/pocketroofline/issues/new?template=device-capture.yml);
captures are checked with `harness/finalize.py --check` before they land in
`results/`.

## Status

| Phase | Deliverable | State |
|---|---|---|
| 0 | Protocol, schema, priority stake | **done** |
| 1 | M1 anchor + A15 first numbers, one model across both | **done** (warm start; cold-start session owed) |
| 2 | Full matrix (models × quants × backends); bandwidth microbenchmark; preprint | **started**: measured bandwidth ceiling for the A16 (Headroom probe); A15 ceiling, full matrix and preprint not started |
| 3 | Community submission ledger | not started |

Published so far: one model (TinyLlama-1.1B Q4_0), one backend
(llama.cpp-Metal), three devices (two phones and the M1 control), three
regimes, five repeats each. The iPhone 13 session is warm-start; the iPhone 15
Plus has three sessions (one warm, two cold) and an unexplained SILO step. The
STREAM-style bandwidth ceiling of METHODOLOGY §3 is measured for the A16 only.
Not yet measured: other models and quantisations, MLC and Core ML backends, the
A15's bandwidth ceiling, a cold-start iPhone 13 session, energy per token, and
any device beyond these three. This section is the current truth and will be kept current.

## Layout

```
METHODOLOGY.md      measurement protocol, fixed before data collection
PRIOR_ART.md        what exists already, and what this adds
schema/             result file schema; every published number conforms
harness/            build + run instructions per backend
app/                iOS app: run the benchmark on your phone, submit a capture
results/            raw runs, one file per session, never edited after commit
  captures/         device captures as exported, from which the run records were finalized
  bandwidth/        Headroom probe reports: measured bandwidth ceilings (METHODOLOGY §3)
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
