# Prior art, and what PocketRoofline adds

Written so a reviewer does not have to ask "hasn't this been done?" — and so the
answer is checkable rather than asserted. Every row below was read before it was
summarized.

## The three closest works

### RooflineBench — Bi et al., arXiv:2602.11506 (v1 Feb 2026, v4 Aug 2026)

The direct parent. Establishes the roofline / operational-intensity framework
for on-device LLMs, introduces Relative Inference Potential, and characterizes
how OI varies with sequence length and model depth.

- **Platforms:** RTX 3090, RTX 3070 Ti Laptop, Apple M1 Pro, Jetson Orin Nano
  Super 8G, Raspberry Pi 5. Reported ridge points span 8.98 to 38.00 FLOPs/Byte.
- **No smartphone is evaluated.**
- **No error bars, confidence intervals, or repeated-run variance are reported.**
- Future Work §B states the authors "aim to scale our testing to a more diverse
  array of heterogeneous edge devices" and to investigate how inference engines
  affect OI and realized throughput.
- Code: [banbu-ai/roofline_bench](https://github.com/banbu-ai/roofline_bench).

### Edge deployment of SLMs — Prieto & Abad, arXiv:2511.22334 (Nov 2025)

Comparative inference performance and energy efficiency across backends, with
bandwidth normalization for cross-architecture fairness and EDP as a combined
metric.

- **Platforms:** commercial Intel and ARM CPUs, NVIDIA GPUs, and RaiderChip
  NPUs — embedded and edge-class parts, not shipping smartphones.
- Does not use a roofline model; reports no confidence intervals.

### Local LLM inference on Apple Silicon — Rajesh et al., arXiv:2511.05502 (Oct 2025)

Systematic comparison of five runtimes — MLX, MLC-LLM, llama.cpp, Ollama, and
PyTorch MPS — the closest work on the Apple side, and the reason the backend
axis here is not a novelty claim.

- **Platform:** a single Mac Studio, M2 Ultra, 192 GB unified memory. **No phones.**
- Does not use a roofline model; reports no confidence intervals.

## The gap, stated precisely

Phone inference *has* been measured. Roofline analysis *has* been applied to
edge hardware. Apple Silicon runtimes *have* been compared. What does not exist
in any of the three:

| | RooflineBench | Prieto & Abad | Rajesh et al. | PocketRoofline |
|---|---|---|---|---|
| Roofline / OI framework | yes | no | no | yes |
| Shipping smartphone SoC | no | no | no | **yes** |
| Confidence intervals | no | no | no | **yes** |
| Thermal state controlled + reported | not reported | not reported | not reported | **yes** |
| Re-run across OS / runtime versions | no | no | no | **yes** |

The contribution is the intersection, not any single column. Specifically:

1. **Roofline treatment of a phone SoC**, where the ridge point must be measured
   rather than cited, because Apple publishes neither peak FLOPS nor peak
   bandwidth for the A15.
2. **Stated uncertainty**, on a device class where thermal state and DVFS make
   single-run point estimates unreliable in a way they are not on a desktop GPU.
3. **A longitudinal record** across OS point releases and runtime versions —
   the axis that cannot be added retroactively by anyone, including by this
   project, later.

## Claims this project will not make

- Not "the first benchmark of LLMs on phones." It is not.
- Not "phone inference is unmeasured." It is measured; it is not *roofline-
  characterized with stated uncertainty over time*.
- Not a claim of superiority over RooflineBench. This extends their framework to
  a device class they name as future work, and the data is offered upstream.

If any of the above becomes false — including because RooflineBench v5 adds
phones — this file is updated first, before the README, and the change is dated.
