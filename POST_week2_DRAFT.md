# PocketRoofline — Week-2 launch post (DRAFT, fill in the A15 numbers)

> Publish only after the first real iPhone 13 run lands and `results/` has the
> A15 records. Replace every `<...>` with a measured number. This is the
> timestamp-stake post, not the preprint — "ugly but rigorous" is the goal.

## Assets
- Repo: https://github.com/Umer9538/pocketroofline
- The numbers: `results/` (committed JSON, one record per regime)
- Card: generate after numbers land (a single roofline plot or the SISO/LISO/SILO bar).

================================================================
# LINKEDIN / X (short)
================================================================

Everyone says "on-device LLM." Almost nobody measures on-device — the standard
benchmarks run on desktop GPUs, laptops, a Jetson, a Raspberry Pi. Not phones.

So I measured a phone.

First numbers from an iPhone 13 (A15), Qwen2.5-0.5B Q4_K_M, llama.cpp-Metal,
5 repeats each with thermal state recorded:

▶️ Prefill (128 tok): <PP> tok/s
▶️ Decode (128 tok): <TG> tok/s
▶️ Long context (2048-tok prefill): <LISO_PP> tok/s
▶️ Sustained decode (1024 tok): <SILO_TG> tok/s — thermal state <nominal/fair> throughout

This extends RooflineBench (arXiv:2602.11506) to the device class the phrase is
actually about. Every number has repeats and is committed as JSON you can check;
the matrix re-runs on every iOS and runtime update, so this becomes a record of
how phone inference drifts over time — not a one-off.

Open, MIT, contributions from other devices welcome (iPhone 15 Pro+, Pixel 8+):
https://github.com/Umer9538/pocketroofline

#OnDeviceAI #iOS #LLM #Benchmark #AppleSilicon

================================================================
# r/LocalLLaMA
================================================================

Title: I benchmarked LLM inference on an actual iPhone (A15) with the roofline
method — first numbers, open data

Body: RooflineBench (arXiv:2602.11506) characterizes on-device LLM inference
across an RTX 3090, a 3070 Ti laptop, an M1 Pro, a Jetson Orin Nano, and a
Raspberry Pi 5 — but no phone. I've started extending the methodology to
smartphone silicon, beginning with an iPhone 13 (A15). First run below; protocol
pinned before any number was taken (airplane mode, unplugged, thermal state per
repeat, 5 repeats, synthetic-token regimes matching llama-bench).

<paste the SISO/LISO/SILO table here>

Everything is committed JSON (github.com/Umer9538/pocketroofline). It re-runs on
every OS/runtime update to track drift. Method critiques welcome, and if you've
got an iPhone 15 Pro+ or Pixel 8+ the harness takes ~10 min to add your device.

================================================================
# NOTES
================================================================
- Lead with the gap ("nobody measures phones"), not the tool.
- Never claim ANE/GPU peak you didn't measure; llama.cpp-Metal is GPU-path only.
- If decode shows thermal throttling on SILO, that IS a finding — report the
  sustained-vs-peak gap honestly; it's the most interesting phone-specific result.
