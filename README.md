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

## What this adds to the roofline picture

**1. Phone SoCs.** Operational intensity, attainable throughput, and the
empirical ridge point for A15-class silicon under llama.cpp-Metal, MLC, and
Core ML — measured on hardware that is thermally constrained, battery-powered,
and running a general-purpose OS that is not under our control.

**2. Confidence intervals on every number.** RooflineBench reports point
estimates; it does not report error bars, repeated-run variance, or confidence
intervals. Phone measurements need them more than desktop measurements do —
thermal state, background activity, and DVFS make a single run close to
meaningless. Every figure published here carries a Wilson or Newcombe interval
computed by [`unswayed`](https://github.com/Umer9538/unswayed), and every
underlying run is published alongside it.

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
| 0 | Protocol, schema, priority stake | **in progress** |
| 1 | M1 calibration anchor vs RooflineBench; A15 first numbers | not started |
| 2 | Full matrix; preprint; leaderboard v1 | not started |
| 3 | Community submission ledger | not started |

No measurements have been published yet. This section is the current truth and
will be kept current.

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
