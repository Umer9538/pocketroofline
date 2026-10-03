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
| LISO 2048/128 | 402.6 (−12.3%) | 42.42 (sd 0.08) | fair → **serious** |
| SILO 128/1024 | 406.9 (−23.9%) | **40.53 → 30.93 (−23.7%)** | serious throughout |

**Headline:** peak decode overstates sustained decode by **38%**. SILO's decline is
perfectly monotonic (Spearman rho −1.00) while SISO holds to 0.9% CV — so it is
thermal, not noise.

**The control (same model, same regimes, same commit, same day):**

| Device | SISO decode | LISO decode | SILO (5 long generations) |
|---|---|---|---|
| iPhone 13 (A15) | 42.80 | 42.42 | **40.53 → 30.93** (rho −1.00) |
| MacBook Pro (M1) | 61.10 | 62.32 | **64.55 flat** (rho +0.10) |

**Roofline placement:** decode reads all 0.636 GB of weights per token, so the A15
achieves 27.2 GB/s (64–80% of published peak) vs the M1's 38.9 GB/s (57%). The phone
uses *more* of its memory system than the laptop — it just has a much smaller ceiling,
and throttling takes it down to 19.7 GB/s.

> Recommended: run the cold-start session first (10-minute cooldown to `nominal`)
> and publish both. "Warm start vs cold start on the same phone" is a second
> finding and pre-empts the first critique a reviewer will make.

================================================================
# MEDIUM ARTICLE
================================================================

**Title:** Your phone runs a language model at 42 tokens per second. For about a minute.

**Subtitle:** Every on-device LLM benchmark I could find runs on desktop GPUs, laptops and single-board computers. So I measured an actual phone — and the number everyone quotes turns out to be the one you almost never get.

[HEADER IMAGE: screenshot of the hero + throttling chart from umer9538.github.io/pocketroofline]

---

### The number that isn't the number

Run a 1B-parameter model on an iPhone 13 and ask it something short. You get about **42 tokens per second**. That is a real measurement, and it is reproducible to within 1%.

Now ask it for five long answers in a row — the way anyone actually uses a chat app:

```
40.5  →  40.4  →  37.5  →  33.0  →  30.9   tokens/sec
```

Every run slower than the one before. By the fifth, the phone is delivering **30.9 tok/s** — and it stays there. It got hot, throttled, and did not recover.

So the honest version of the headline number is: your phone runs a language model at 42 tokens per second *for about a minute*. Peak overstates sustained by **38%**.

### What was missing

The current state of the art for on-device LLM benchmarking is [RooflineBench](https://arxiv.org/abs/2602.11506) (Bi et al., arXiv:2602.11506). It is a genuinely good framework — a roofline treatment of inference, operational intensity, the efficiency traps that appear as model depth grows. It evaluates across five platforms:

- NVIDIA RTX 3090
- RTX 3070 Ti Laptop
- Apple M1 Pro
- Jetson Orin Nano Super
- Raspberry Pi 5

**None of them is a phone.** And every one of them is either mains-powered, actively cooled, or both.

That is not a criticism of the paper — its platform set is what it is, and the authors say in their own future work that they intend to extend to more edge devices. But "on-device LLM" in ordinary usage means *the phone in your pocket*, and the phone is the one device class whose defining constraint — a sealed passively-cooled box running on a battery — is absent from the entire platform list.

So I started measuring phones, using their methodology.

*Correction added after publishing:* the thermal collapse itself had been measured before this post. [arXiv:2603.23640](https://arxiv.org/abs/2603.23640) (March 2026) ran an iPhone 16 Pro under sustained load with MLX and saw it fall from 40.5 to 23.7 tok/s over 20 runs, thermal state logged. What this project adds is the roofline placement, a plugged-in control, and open per-repeat data re-run on every OS build.

### The method, fixed before any number was taken

The protocol is boring on purpose, and it was committed to the repository before the first measurement:

- **Three frozen regimes**, borrowing RooflineBench's naming: SISO (128 tokens in, 128 out), LISO (2048 in, 128 out), SILO (128 in, 1024 out).
- **Five repeats each**, one unrecorded warmup, so that run-to-run variance is measured rather than assumed.
- **`ProcessInfo.thermalState` recorded at the start and end of every single repeat.** This is the field that everything else turns out to depend on.
- **Airplane mode, Wi-Fi and Bluetooth off, unplugged, app in the foreground.** Active radios draw power and make heat; a charging cable changes the thermal picture entirely.
- **Every repeat published**, never summarised away. The page's figures are generated from the committed JSON — there is no number on it that I typed by hand.

Device: iPhone 13 (A15 Bionic), iOS 26.6.1 build 23G83. Model: TinyLlama-1.1B Q4_0. Runtime: llama.cpp-Metal at commit `95ef7fc`, weights pinned by SHA-256.

### The finding, and the control that makes it a finding

Here is the whole session:

| Regime | Prefill tok/s | Decode tok/s | Thermal state |
|---|---|---|---|
| SISO (128/128) | 504.0 | **42.80** (sd 0.37) | fair, stable |
| LISO (2048/128) | 402.6 | 42.42 (sd 0.08) | fair → **serious** |
| SILO (128/1024) | 406.9 | **40.53 → 30.93** | serious throughout |

The SILO decline is **monotonic across all five repeats** — Spearman rho = −1.00, a perfect rank trend. Not scattered, not noisy: every repeat strictly slower than its predecessor.

The reason that is a finding rather than an anecdote is sitting in the first row. In SISO, decode is stable to a **standard deviation of 0.37 tok/s — 0.9% variation.** The same metric, the same device, the same code, measured minutes apart. So when the same measurement falls by a quarter under sustained load, it cannot be dismissed as measurement scatter. The phone is throttling.

Prefill falls in step, −23.9%. The device enters `serious` thermal state partway through the second regime and never returns to `fair` for the rest of the session.

### The same workload, plugged in

The obvious objection is that maybe this is just what LLM inference does, everywhere. So I ran the **identical** workload — same model, same quantisation, same regimes, same llama.cpp commit, same day — on a MacBook Pro (M1):

| Device | SISO decode | LISO decode | SILO, five long generations |
|---|---|---|---|
| iPhone 13 (A15) | 42.80 | 42.42 | **40.53 → 30.93** (rho −1.00) |
| MacBook Pro (M1) | 61.10 | 62.32 | **64.55, flat** (rho +0.10) |

The laptop does not decline at all. If anything it drifts slightly upward as caches warm. It is mains-powered and has a fan, so the workload that costs the phone a quarter of its throughput costs the laptop nothing.

That is the entire argument for measuring phones directly rather than extrapolating from edge boards: **the effect only exists on the hardware the roofline work was not testing.**

### Where this sits on the roofline

Single-stream autoregressive decode reads every weight exactly once per token. With 0.636 GB of quantised weights, decode throughput converts straight into achieved memory bandwidth — which is what places this workload on a roofline, firmly in the memory-bound region. That, incidentally, is *why* decode is what throttling destroys and prefill suffers less: prefill has arithmetic intensity to spare, decode is starved for bandwidth.

| SoC | Achieved GB/s | Share of published peak |
|---|---|---|
| A15 (iPhone 13) | 27.2 | **64–80%** |
| M1 (MacBook Pro) | 38.9 | **57%** |
| A15, after throttling | **19.7** | 54–68% |

This inverts the story you would expect. **The phone extracts a larger fraction of its memory system than the laptop does.** The A15 is not inefficient — it is efficient, working against a much smaller ceiling, and then thermal throttling takes away a quarter of what it had.

I want to be precise about the weakest part of that table: the percentages depend on a *published vendor* peak-bandwidth figure, not one I measured. Public sources do not even agree on the A15 — 34.1 GB/s (64-bit LPDDR4X-4266) versus 42.7 GB/s appear in different places — which is why the utilisation is given as a range rather than a single confident number. A STREAM-style measured ceiling is owed and will replace it. Until then the achieved GB/s column is the result and the percentage column is an indication.

### What I am not claiming

- **This is a warm start.** The device began at thermal state `fair`, not `nominal` — I did not achieve the ten-minute ambient cooldown my own protocol calls for. These are warm-start figures and they are labelled that way in every record. A cold-start session is owed, and it will be published beside this one rather than replacing it.
- **One repeat is flagged.** The LISO repeat whose thermal state changed mid-run is excluded from steady-state aggregates and retained in full in the data, because deleting inconvenient measurements is how benchmarks become fiction.
- **The mean of the throttling regime is meaningless** and is marked as such. A series that declines monotonically is non-stationary; averaging it produces a number that describes no moment that actually occurred. The curve is the result, not its average.
- **One device is one device.** This is a single iPhone 13, on one OS build, at one thermal state, with one model, one quantisation and one runtime.
- **No ANE or peak-FLOPS claims.** llama.cpp-Metal is the GPU path. Apple does not publish the Neural Engine's peak figures, so anything I said about them would be invention.

### Why it re-runs forever

The matrix is pinned and versioned, and it is re-run on every iOS point release and every llama.cpp version bump. A snapshot benchmark tells you what a phone did once. Run longitudinally, the same matrix tells you what changed underneath it — and unlike a snapshot, that record cannot be reconstructed later by anyone who starts after you do.

This is the same discipline behind [underfoot](https://umer9538.github.io/underfoot/), which tracks what OS updates silently change in the AI models Apple and Google ship inside the operating system, and [unswayed](https://github.com/Umer9538/unswayed), which decides with confidence intervals whether a model swap actually regressed anything.

### If you have a phone

The scarcest resource in this project is eligible hardware. A capture takes about ten minutes, and every device added is a column of a record nobody can backfill.

- 📊 Charts, tables, and every repeat: **https://umer9538.github.io/pocketroofline/**
- ⭐ Data, harness, and methodology (MIT): **https://github.com/Umer9538/pocketroofline**

Method critiques are more welcome than praise. If the protocol is wrong, I would rather find out in a comment than in a citation.

**Tags:** Machine Learning, iOS, Benchmarking, On Device AI, LLM

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

Why the usual benchmarks miss this: the standard benchmarks for on-device AI run on desktop
GPUs, laptops, and single-board computers. Plugged in, actively cooled, no
thermal envelope like a phone in your hand. So I started measuring phones, using
the same roofline methodology, publishing every repeat and every caveat.

I ran the identical workload on a MacBook M1 as a control: it holds 64.6 tok/s flat
across all five long generations. Same model, same code, same day. The laptop is
plugged in and actively cooled — it simply cannot show you what a phone does.

Open data, MIT: https://github.com/Umer9538/pocketroofline
Charts and every repeat: https://umer9538.github.io/pocketroofline/

#OnDeviceAI #iOS #LLM #MobileDevelopment #OpenSource

================================================================
# r/LocalLLaMA
================================================================

**Title:** I ran a roofline benchmark on an actual iPhone — sustained decode is 28% below peak

RooflineBench (arXiv:2602.11506) characterises on-device LLM inference across an
RTX 3090, a 3070 Ti laptop, an M1 Pro, a Jetson Orin Nano and a Raspberry Pi 5 —
no phone anywhere in the platform set. I've started extending the methodology to
phone silicon. First session, iPhone 13 (A15), TinyLlama-1.1B Q4_0, llama.cpp-Metal:

    SISO 128/128    prefill 504.0    decode 42.80  (sd 0.37, CV 0.9%)
    LISO 2048/128   prefill 402.6    decode 42.42  (sd 0.08)
    SILO 128/1024   prefill 406.9    decode 40.53 -> 30.93  (-23.7%)

The SILO decline is monotonic across all five repeats (Spearman rho -1.00) while
decode in SISO is stable to 0.9% CV, so it's thermal throttling rather than
measurement scatter. Device reached `serious` thermal state during LISO and stayed
there. Fifth-repeat sustained (30.93) is 27.7% below peak (42.80) — put the other
way, peak overstates sustained by 38%.

Protocol: airplane mode, Wi-Fi and Bluetooth off, unplugged, foreground app,
synthetic-token regimes (same approach as llama-bench), one unrecorded warmup,
`ProcessInfo.thermalState` captured at the start and end of every repeat.

Stated limitations, because they matter: the session started at thermal state
`fair` rather than `nominal` (the 10-minute cooldown wasn't achieved), so these
are warm-start figures and labelled as such; the one repeat whose thermal state
changed mid-run is flagged and excluded from aggregates but retained in the data;
and SILO's mean is explicitly not a steady-state number since the series is
non-stationary — the curve is the result, not its average.

Control, run the same day with the identical model/regimes/commit — a MacBook Pro
(M1) on mains power holds decode flat at 64.55 tok/s (rho +0.10) across the same five
long generations. Thermal behaviour is the thing phone benchmarks have to capture, and
a plugged-in laptop, a Jetson or a Pi structurally cannot show it.

Roofline placement: decode reads all 0.636 GB of weights per token, so achieved memory
bandwidth is 27.2 GB/s on the A15 (64-80% of published peak — sources disagree on the
A15's peak, so it's a range, and a STREAM ceiling is owed) vs 38.9 GB/s on the M1
(57%). The phone extracts a higher fraction of its memory system; it just has a much
smaller ceiling, and throttling drops it to 19.7 GB/s.

Related work, so nobody has to point it out: arXiv:2603.23640 measured an iPhone 16 Pro under
sustained load with MLX (-41.5% over 20 runs), so the thermal effect itself is not new. What is
new here is the roofline placement (achieved bandwidth vs the device ceiling), the plugged-in
control, and open per-repeat data re-run on every OS build.

Everything is committed JSON and the page's numbers are generated from it, not
typed: https://github.com/Umer9538/pocketroofline
Page: https://umer9538.github.io/pocketroofline/

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
monotonically to 30.93 tok/s over five consecutive long generations — 28% below
peak (peak overstates sustained by 38%), Spearman rho -1.00, with the device
pinned in `serious` thermal state. Every repeat is committed as JSON, the page's figures are generated
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
