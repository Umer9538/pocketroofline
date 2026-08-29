# Methodology

This protocol is fixed **before** data collection. Where it changes, the change
is committed with a rationale and the affected results are re-run and re-dated —
never silently rebased.

The measurement discipline is the contribution. A phone throughput number
without a thermal state, a repeat count, and an interval is not a result.

---

## 1. What is measured

Per (model, quantization, backend, device, OS build):

| Quantity | Unit | How |
|---|---|---|
| Prefill throughput | tok/s | fixed prompt lengths, batch of one |
| Decode throughput | tok/s | fixed generation length, greedy |
| Time to first token | ms | wall clock, prompt submit to first token |
| Peak resident memory | MB | OS-reported, sampled at 10 Hz |
| Operational intensity | FLOPs/byte | analytic, from model config (see §3) |
| Attainable performance | GFLOPS | derived: OI x measured throughput |
| Energy per token | mWh/tok | battery-drain protocol (§6) |

Prefill and decode are reported separately and never averaged into one
"tokens per second". They sit on opposite sides of the ridge point — prefill is
compute-bound, decode is bandwidth-bound — and collapsing them is the specific
error the roofline model exists to prevent.

## 2. The pinned matrix

The matrix is versioned. `matrix/v1.json` is the frozen definition; a change to
any axis creates `v2` and does not retroactively alter `v1` results.

- **Models:** 0.5B-4B parameter class, dense, instruction-tuned.
- **Quantization:** Q4_K_M and Q8_0 (matching RooflineBench's edge tiers), plus
  FP16 where memory allows.
- **Backends:** llama.cpp-Metal, MLC-LLM, Core ML (ANE and GPU compute units).
- **Sequence regimes:** the short-in/short-out, long-in/short-out, and
  short-in/long-out cases, so prefill-bound and decode-bound behavior are
  separable.

## 3. Constructing a roofline for a phone SoC

RooflineBench derives ridge points from published peak FLOPS and peak memory
bandwidth. **Apple publishes neither for the A15.** Two consequences:

1. **Bandwidth is measured, not cited.** A STREAM-style Metal microbenchmark
   (copy / scale / add / triad over buffers exceeding last-level cache)
   establishes an empirical sustained-bandwidth ceiling. The reported ridge point
   is therefore an *empirical* ridge point and is labelled as one everywhere it
   appears.
2. **The ANE gets a measured ceiling, not a roofline.** With no published peak
   throughput and no counter access, an ANE roofline cannot be constructed
   honestly. Core ML ANE results are reported as measured attainable performance
   with no ridge line drawn.

Operational intensity is computed analytically from model configuration
(layers, hidden size, heads, KV-cache geometry, sequence length) following
RooflineBench's formulation, so the two datasets remain comparable. The
derivation used is recorded in `schema/run.schema.json` under `oi_method`.

## 4. Repeats and uncertainty

- **Minimum 5 runs** per cell; 20 where a difference is being claimed.
- Every individual run is published. Aggregates never replace raw runs.
- Throughput is summarized as median with a bootstrap interval; pass/fail style
  proportions use Wilson intervals; differences between two cells use Newcombe
  intervals — computed by [`unswayed`](https://github.com/Umer9538/unswayed),
  the same implementation used for its published verdicts.
- **A difference whose interval crosses zero is reported as undecided, not as a
  result.** No leaderboard delta is claimed without an interval that excludes
  zero.

## 5. Thermal protocol

Phones throttle. Unstated thermal state is the single largest source of
irreproducibility in phone benchmarking.

- Device in **airplane mode**, screen at a fixed brightness, no other foreground app.
- **Cooldown to a fixed baseline** before each run: device idle at ambient until
  the thermal state reads nominal, minimum 10 minutes between runs.
- Ambient temperature recorded per session.
- Every run records `ProcessInfo.thermalState` at start and end. **A run whose
  thermal state changed mid-run is flagged, published, and excluded from the
  steady-state aggregate** — it is not silently dropped.
- **Sustained-load curves are reported separately**: throughput as a function of
  elapsed time under continuous generation, to the point of stable throttling.
  Peak throughput and sustained throughput are both published. Peak alone is
  the number that misleads.

## 6. Energy protocol

Reported as **system-level battery drain**, and framed that way in every figure:

- Airplane mode, fixed brightness, battery between 80% and 40% (avoiding the
  non-linear charge curve at either end), charger disconnected.
- Fixed workload repeated N times; drain measured across the block, divided by
  total tokens generated.
- Idle drain measured under identical conditions and subtracted.
- **This is not per-component power instrumentation.** It attributes whole-device
  drain to the workload under controlled conditions. Any claim about SoC, GPU, or
  ANE power specifically is out of scope.

## 7. What invalidates a run

A run is marked invalid, published as invalid, and excluded from aggregates if:

- thermal state changed mid-run (§5);
- the device was charging, or off airplane mode;
- background OS activity was detected (backup, indexing, update staging);
- the OS build or backend version does not match the run's declared metadata;
- resident memory hit the jetsam limit and the process was terminated.

Invalid runs stay in `results/` with `"valid": false` and a reason. The
invalidation rate is itself a published statistic.

## 8. Longitudinal re-runs

From the moment the matrix is pinned:

- Re-run the full `v1` matrix on **every iOS point release** and **every tagged
  llama.cpp / MLC release**.
- Diff against the previous run with `vouch`; a regression outside its interval
  opens an issue and appears in the drift feed.
- OS build, backend commit SHA, and model file SHA-256 are recorded per run, so
  any published number can be traced to exactly what produced it.

Nothing about this layer can be reconstructed after the fact. That is its point.
