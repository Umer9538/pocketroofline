# PocketRoofline — launch posts (real numbers, ready to publish)

All figures below are measured and committed. Nothing here is a placeholder.

**Assets**
- Page (chart + tables + stated limits): https://umer9538.github.io/pocketroofline/ *(enable Pages: Settings → Pages → main /docs)*
- Repo: https://github.com/Umer9538/pocketroofline
- Records: `results/` — one JSON per regime, every repeat retained
- Card image: screenshot the hero + chart from the page

**The session**
iPhone 13 (A15) · iOS 26.6.1 (23G83) · TinyLlama-1.1B Q4_0 · llama.cpp-Metal `95ef7fc`
airplane mode, Wi-Fi and Bluetooth off, unplugged · 3 regimes × 5 repeats

| Regime | Prefill tok/s | Decode tok/s | Thermal |
|---|---|---|---|
| SISO 128/128 | 504.0 | **42.80** (sd 0.37, CV 0.9%) | fair, stable |
| LISO 2048/128 | 413.0 (−12.3%) | 42.42 (sd 0.08) | fair → **serious** |
| SILO 128/1024 | 406.9 (−23.9%) | **40.53 → 30.93 (−23.7%)** | serious throughout |

**Headline:** peak decode overstates sustained decode by **38%**. SILO's decline is
perfectly monotonic (Spearman rho −1.00) while SISO holds to 0.9% CV — so it is
thermal, not noise.

> Recommended: run the cold-start session first (10-minute cooldown to `nominal`)
> and publish both. "Warm start vs cold start on the same phone" is a second
> finding and pre-empts the first critique a reviewer will make.

================================================================
# LINKEDIN (short — the format that works)
================================================================

Your phone can run a language model at 42 tokens/second.

For about a minute.

I measured LLM inference on an iPhone 13 the way you'd measure a server: same
workload, five consecutive runs, thermal state recorded every time.

Short prompts: 42.8 tokens/sec, rock steady — under 1% variation between runs.

Then I asked it to generate long responses, five times in a row:

40.5 → 40.4 → 37.5 → 33.0 → 30.9

Every single run slower than the one before. The phone got hot, throttled, and
never recovered while I kept using it. Peak speed overstates real sustained speed
by 38%.

That gap matters, because every "tokens per second on iPhone" number you've seen
quoted is a peak number — the first minute, on a cool phone.

Why nobody caught this: the standard benchmarks for on-device AI run on desktop
GPUs, laptops, and single-board computers. Plugged in, actively cooled, no
thermal envelope like a phone in your hand. So I started measuring phones, using
the same roofline methodology, publishing every repeat and every caveat.

Open data, MIT: https://github.com/Umer9538/pocketroofline

#OnDeviceAI #iOS #LLM #MobileDevelopment #OpenSource

================================================================
# r/LocalLLaMA
================================================================

**Title:** I ran a roofline benchmark on an actual iPhone — sustained decode is 38% below peak

RooflineBench (arXiv:2602.11506) characterises on-device LLM inference across an
RTX 3090, a 3070 Ti laptop, an M1 Pro, a Jetson Orin Nano and a Raspberry Pi 5 —
no phone anywhere in the platform set. I've started extending the methodology to
phone silicon. First session, iPhone 13 (A15), TinyLlama-1.1B Q4_0, llama.cpp-Metal:

    SISO 128/128    prefill 504.0    decode 42.80  (sd 0.37, CV 0.9%)
    LISO 2048/128   prefill 413.0    decode 42.42  (sd 0.08)
    SILO 128/1024   prefill 406.9    decode 40.53 -> 30.93  (-23.7%)

The SILO decline is monotonic across all five repeats (Spearman rho -1.00) while
decode in SISO is stable to 0.9% CV, so it's thermal throttling rather than
measurement scatter. Device reached `serious` thermal state during LISO and stayed
there. Peak (42.80) vs fifth-repeat sustained (30.93) = 38%.

Protocol: airplane mode, Wi-Fi and Bluetooth off, unplugged, foreground app,
synthetic-token regimes (same approach as llama-bench), one unrecorded warmup,
`ProcessInfo.thermalState` captured at the start and end of every repeat.

Stated limitations, because they matter: the session started at thermal state
`fair` rather than `nominal` (the 10-minute cooldown wasn't achieved), so these
are warm-start figures and labelled as such; the one repeat whose thermal state
changed mid-run is flagged and excluded from aggregates but retained in the data;
and SILO's mean is explicitly not a steady-state number since the series is
non-stationary — the curve is the result, not its average.

Everything is committed JSON and the page's numbers are generated from it, not
typed: https://github.com/Umer9538/pocketroofline

Method critiques welcome. If you have an iPhone 15 Pro+ or a Pixel 8+, a capture
takes about ten minutes and adds a device to the matrix.

================================================================
# HACKER NEWS (hold until the cold-start run is in)
================================================================

**Title:** Show HN: Roofline benchmarks for LLM inference on phones, not edge boards

**First comment:** On-device LLM benchmarks are run on desktop GPUs, laptops,
Jetsons and Raspberry Pis — devices that are plugged in and thermally unlike the
phone the phrase is usually about. PocketRoofline extends RooflineBench's
methodology (arXiv:2602.11506) to phone silicon. First session on an iPhone 13
(A15): decode is stable at 42.80 tok/s for short generations (0.9% CV) but falls
monotonically to 30.93 tok/s over five consecutive long generations — a 38%
peak-vs-sustained gap, Spearman rho -1.00, with the device pinned in `serious`
thermal state. Every repeat is committed as JSON, the page's figures are generated
from those files, and the limitations (warm start, one flagged repeat, a
non-stationary series whose mean is meaningless) are stated on the page rather
than buried. The matrix re-runs on every OS and runtime update, so this becomes a
drift record rather than a snapshot. Critiques of the method very welcome;
captures from other devices even more so.

================================================================
# NOTES
================================================================
- Lead with the reader's phone, not the tool. "42 tok/s — for about a minute."
- Never quote SILO's mean as a throughput figure; it is a non-stationary series.
- Do not claim ANE or GPU peak FLOPS — llama.cpp-Metal is the GPU path only, and
  no bandwidth microbenchmark has been run yet.
- The honest caveats are an asset here: they are what separates this from a
  screenshot of a phone app's token counter.
