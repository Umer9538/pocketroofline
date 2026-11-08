#!/usr/bin/env python3
"""Read a PocketRoofline recovery capture: after the phone is heat-soaked, how long does decode
take to get back to its cold speed?

The recovery test (matrixVersion "recovery-ladder-1") runs an unrecorded warmup, then a HEAT
phase of SILO 128/1024 x 3 back to back (3 s pauses), then a ladder of rests (30, 60, 120, 300 s),
each followed by one PROBE, a SISO 128/128 decode. The rests are cumulative: the phone keeps
cooling through every rest and probe, so each probe is also placed by its time since the heat
phase ended. The screen stays still throughout.

Printed: the heat-phase repeats with their window rates; each probe's decode as a share of the
COLD REFERENCE (the first 64-token window of the first heat repeat, the coolest point of the run)
and of this phone's matrix v1 SISO decode mean when results/ has a record for its hardware
identifier (read only); the thermal transitions; and one sentence of reading. The reading is
never stronger than the data: one run, one probe per rest, so a recovery time is bounded between
two probes, never measured exactly.

Recovery captures are not matrix v1 runs. They live in results/recovery/, finalize.py refuses
them, and report.py and validate.py never read them.

Usage (from the repo root):
    python3 harness/recovery.py results/recovery/pocketroofline-recovery-<unix>.json
"""
import json, pathlib, statistics as st, sys

sys.dont_write_bytecode = True  # keep harness/ free of __pycache__
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from diagnose import reference_siso, fmt_pct, pct  # noqa: E402

RECOVERED_PCT = 95.0  # a probe at or above 95% of the cold reference counts as recovered
HEATED_PCT = 10.0     # the heat phase must slow decode by 10% or more (its last 3 windows vs the cold
                      # reference) for there to be anything to recover from
HELD = 3              # windows at the end of the heat phase that set the heat-soaked rate
NOISE_PCT = 5.0       # window-to-window noise in the heat phase above this, and a 95% line can't be
                      # told from noise: no reading


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def load(path):
    try:
        cap = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        die(f"cannot read {path}: {e}")
    if cap.get("kind") != "recovery" or not str(cap.get("matrixVersion", "")).startswith("recovery-"):
        die(f"{path} is not a recovery capture (kind {cap.get('kind')!r}, matrixVersion "
            f"{cap.get('matrixVersion')!r}); diagnostics go through harness/diagnose.py, benchmark "
            "captures through harness/finalize.py")
    if not cap.get("heat") or not cap["heat"][0].get("windows"):
        die(f"{path} has no heat-phase window trace")
    return cap


def noise_of(heat):
    """Median, over heat repeats, of the median absolute deviation of window-to-window changes (%).
    A steady trend changes by about the same amount each window, so it adds little; noise does."""
    per_repeat = []
    for r in heat:
        rates = [w["tokensPerSec"] for w in r["windows"]]
        changes = [pct(a, b) for a, b in zip(rates, rates[1:])]
        if len(changes) >= 3:
            mid = st.median(changes)
            per_repeat.append(st.median(abs(c - mid) for c in changes))
    return st.median(per_repeat) if per_repeat else None


def share(value, ref):
    return value / ref * 100 if ref else None


def fmt_share(x):
    return "n/a" if x is None else f"{x:.0f}%"


def secs(x):
    return f"{x:.0f} s" if abs(x - round(x)) < 0.05 else f"{x:.1f} s"


def thermal_events(cap):
    """(seconds, where, state) for every thermal reading, in time order."""
    events = []
    for r in cap["heat"]:
        name = f"heat {r['index'] + 1}"
        events.append((r["startSeconds"], f"{name} start", r["thermalStateStart"]))
        for i, w in enumerate(r["windows"]):
            events.append((w["secondsSinceStart"], f"{name} window {i + 1}", w["thermalState"]))
        end = r["windows"][-1]["secondsSinceStart"] if r["windows"] else r["startSeconds"]
        events.append((end, f"{name} end", r["thermalStateEnd"]))
    for p in cap.get("probes", []):
        rung = p["index"] + 1
        events.append((p["restStartSeconds"], f"rest {rung} start", p["thermalAtRestStart"]))
        for c in p.get("thermalChangesDuringRest", []):
            events.append((c["secondsSinceStart"], f"during rest {rung}", c["state"]))
        res = p["result"]
        events.append((res["startSeconds"], f"rest {rung} end / probe {rung} start", p["thermalAtRestEnd"]))
        for i, w in enumerate(res["windows"]):
            events.append((w["secondsSinceStart"], f"probe {rung} window {i + 1}", w["thermalState"]))
        end = res["windows"][-1]["secondsSinceStart"] if res["windows"] else res["startSeconds"]
        events.append((end, f"probe {rung} end", p["result"]["thermalStateEnd"]))
    events.sort(key=lambda e: e[0])
    return events


def reading(cap, cold, soaked_pct, noise, probes):
    """One sentence on recovery, from the probes' shares of the cold reference."""
    if not probes:
        return "No reading: the capture has no probes."
    if noise is not None and noise > NOISE_PCT:
        return (f"No reading: the heat-phase windows are too noisy (window-to-window noise {noise:.1f}%, above "
                f"{NOISE_PCT:.0f}%) to tell a probe at {RECOVERED_PCT:.0f}% of the cold rate from one below it.")
    spread = f"{min(p['cold_pct'] for p in probes):.0f}-{max(p['cold_pct'] for p in probes):.0f}%"
    if soaked_pct is None or -soaked_pct < HEATED_PCT:
        if soaked_pct is None:
            how = "the heat-soaked rate could not be computed"
        elif soaked_pct >= 0:
            how = (f"the heat phase did not slow decode at all (its last {HELD} windows ran {fmt_pct(soaked_pct, 0)} "
                   "vs the cold reference)")
        else:
            how = (f"the heat phase slowed decode by only {-soaked_pct:.0f}% (its last {HELD} windows vs the cold "
                   f"reference), under the {HEATED_PCT:.0f}% that counts as heat-soaked")
        return (f"No recovery reading: {how}, so there was nothing measurable to recover from; the probes ran at "
                f"{spread} of the cold rate.")

    def where(p):
        return f"after the {secs(p['restSecondsPlanned'])} rest, {secs(p['secondsSinceHeatEnd'])} after the heat phase ended"

    hit = next((i for i, p in enumerate(probes) if p["cold_pct"] >= RECOVERED_PCT), None)
    if hit is None:
        last = probes[-1]
        return (f"Not recovered within the ladder: the heat phase slowed decode by {-soaked_pct:.0f}%, and no probe "
                f"reached {RECOVERED_PCT:.0f}% of the cold rate; the last, {where(last)}, was at "
                f"{last['cold_pct']:.0f}% (thermal {last['thermalAtRestEnd']} as it began).")
    p = probes[hit]
    text = f"The heat phase slowed decode by {-soaked_pct:.0f}%; "
    if hit == 0:
        text += (f"recovered to >= {RECOVERED_PCT:.0f}% of the cold rate ({p['cold_pct']:.0f}%) by the first probe, "
                 f"{where(p)}, so the ladder cannot say how much sooner it got there")
    else:
        prev = probes[hit - 1]
        text += (f"recovered to >= {RECOVERED_PCT:.0f}% of the cold rate ({p['cold_pct']:.0f}%) {where(p)}; the "
                 f"probe before, {where(prev)}, was at {prev['cold_pct']:.0f}%, so recovery came between "
                 f"{secs(prev['secondsSinceHeatEnd'])} and {secs(p['secondsSinceHeatEnd'])} after the heat phase")
    text += f" (thermal {p['thermalAtRestEnd']} as that probe began)"
    fell = [q for q in probes[hit + 1:] if q["cold_pct"] < RECOVERED_PCT]
    if fell:
        q = min(fell, key=lambda q: q["cold_pct"])
        text += f", but it did not hold: the probe {where(q)}, was back at {q['cold_pct']:.0f}%"
    return text + "."


def main(argv):
    if argv in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if len(argv) != 1:
        print("usage: python3 harness/recovery.py <recovery-capture.json>", file=sys.stderr)
        return 2
    cap = load(argv[0])
    plan = cap.get("plan", {})
    heat = cap["heat"]
    dev, os_, bk, cond = cap["device"], cap["os"], cap["backend"], cap.get("conditions", {})
    simulator = "(Simulator)" in dev.get("model", "") or bk.get("name") == "llama.cpp-cpu"
    scale = plan.get("restScale", 1)
    scaled = scale != 1
    start_state = heat[0]["thermalStateStart"]

    if scaled:
        print("!" * 78)
        print(f"!!! SCALED RESTS (x{scale:g}) — NOT A REAL RUN. Rests were shortened with the debug-only")
        print("!!! -PocketRooflineRecoveryScale argument. Nothing below says how fast a phone cools.")
        print("!" * 78)
    print(f"PocketRoofline recovery test {cap['matrixVersion']}: not matrix v1, never a benchmark record")
    print(f"{dev['model']} ({dev.get('identifier', '?')}) · {dev['soc']} · {os_['name']} {os_['version']} "
          f"({os_['build']}) · {bk['name']} @ {bk.get('commit', '?')[:12]} · app {cap.get('appVersion', '?')}")
    bits = [f"captured {cap['capturedAt']}"]
    if "charging" in cond:
        bits.append("plugged in" if cond["charging"] else "unplugged")
    bits.append("offline" if cond.get("airplaneMode") else "network on")
    bits.append("Low Power Mode on" if cond.get("lowPowerMode") else "Low Power Mode off")
    if "batteryStartPct" in cond and "batteryEndPct" in cond:
        bits.append(f"battery {cond['batteryStartPct']:g}% -> {cond['batteryEndPct']:g}%")
    print(" · ".join(bits))
    if plan:
        w, h, pr = plan.get("warmup", {}), plan.get("heat", {}), plan.get("probe", {})
        rests = ", ".join(secs(r) for r in plan.get("restSecondsPlanned", []))
        nominal = ", ".join(secs(r) for r in plan.get("restSecondsNominal", []))
        print(f"plan: warmup {w.get('promptTokens')}/{w.get('generateTokens')}; heat {h.get('label')} "
              f"{h.get('promptTokens')}/{h.get('generateTokens')} x {h.get('repeats')} "
              f"({plan.get('pauseSeconds', 0):g} s pause before each); rests {rests}"
              + (f" (scaled x{scale:g} from {nominal})" if scaled else "")
              + f", each followed by {pr.get('label')} {pr.get('promptTokens')}/{pr.get('generateTokens')}; "
              f"{plan.get('windowTokens')}-token windows; {plan.get('screen', '?')} screen")
    print(f"start: thermal {start_state}" + (" (cold start)" if start_state == "nominal" else " (not a cold start)"))

    cold = heat[0]["windows"][0]["tokensPerSec"]
    print(f"cold reference: heat 1, window 1 = {cold:.2f} tok/s (the coolest point of this run)")
    ref = reference_siso(cap)
    if ref:
        build = "" if ref["build"] == os_["build"] else f", OS build {ref['build']}, not this run's"
        print(f"matrix v1 reference: this phone's SISO decode mean {ref['mean']:.2f} tok/s "
              f"(results/{ref['file']}{build}, read only)")
    else:
        print("matrix v1 reference: none (no matrix v1 SISO record for this hardware identifier in results/)")
    if simulator:
        print("NOTE: simulator capture (llama.cpp on the Mac's CPU). It checks the pipeline only and says "
              "nothing about any phone.")

    print("\nHeat phase. tok/s; t = seconds since heat 1 began; windows = each "
          f"{plan.get('windowTokens', 64)}-token window in order.")
    for r in heat:
        rates = [w["tokensPerSec"] for w in r["windows"]]
        change = pct(rates[0], rates[-1]) if len(rates) >= 2 else None
        print(f"  heat {r['index'] + 1}  t={r['startSeconds']:6.1f}  decode {r['decodeTokensPerSec']:6.2f} "
              f"({fmt_share(share(r['decodeTokensPerSec'], cold))} of cold)  prefill {r['prefillTokensPerSec']:6.1f}  "
              f"thermal {r['thermalStateStart']} -> {r['thermalStateEnd']}  first->last window {fmt_pct(change)}")
        print("          windows " + " ".join(f"{x:.1f}" for x in rates))
    tail = [w["tokensPerSec"] for w in heat[-1]["windows"]][-HELD:]
    soaked = st.median(tail)
    soaked_pct = pct(cold, soaked)
    noise = noise_of(heat)
    print(f"  heat-soaked rate: median of the last {HELD} windows of heat {len(heat)} = {soaked:.2f} tok/s, "
          f"{fmt_pct(soaked_pct, 0)} vs cold")
    print("  window-to-window noise: " + ("n/a" if noise is None else f"{noise:.1f}%"))

    probes = []
    for p in cap.get("probes", []):
        res = p["result"]
        q = dict(p)
        q["cold_pct"] = share(res["decodeTokensPerSec"], cold)
        probes.append(q)
    print("\nProbes, one per rest. rest = planned (actual); since heat = from the end of the heat phase to the "
          "probe's start; cold = share of the cold reference; v1 = share of the matrix v1 SISO mean; w1 = the "
          "probe's first window as a share of cold (the same token positions); thermal = rest start -> rest end "
          "-> probe end.")
    for p in probes:
        res = p["result"]
        w1 = share(res["windows"][0]["tokensPerSec"], cold) if res.get("windows") else None
        v1 = share(res["decodeTokensPerSec"], ref["mean"]) if ref else None
        print(f"  rest {secs(p['restSecondsPlanned']):>6} ({secs(p['restSecondsActual'])})  since heat "
              f"{secs(p['secondsSinceHeatEnd']):>6}  decode {res['decodeTokensPerSec']:6.2f}  cold "
              f"{fmt_share(p['cold_pct']):>4}  v1 {fmt_share(v1):>4}  w1 {fmt_share(w1):>4}  thermal "
              f"{p['thermalAtRestStart']} -> {p['thermalAtRestEnd']} -> {res['thermalStateEnd']}")
        for c in p.get("thermalChangesDuringRest", []):
            print(f"          during the rest, t={c['secondsSinceStart']:.1f}: thermal -> {c['state']}")

    print("\nThermal transitions:")
    events = thermal_events(cap)
    changes = [(t, where, prev, now) for (_, _, prev), (t, where, now) in zip(events, events[1:]) if now != prev]
    for t, where, prev, now in changes:
        print(f"  t={t:6.1f}  {where}: {prev} -> {now}")
    if not changes:
        print(f"  none: {start_state} throughout")

    print(f"\nReading. Recovered = a probe's decode at >= {RECOVERED_PCT:.0f}% of the cold reference. The heat "
          f"phase must have slowed decode by >= {HEATED_PCT:.0f}% (its last {HELD} windows vs cold) for there to "
          f"be anything to recover from. Above {NOISE_PCT:.0f}% window noise there is no reading. Rests are "
          "cumulative, so times are given since the heat phase ended.")
    prefix = ""
    if scaled:
        prefix += f"[SCALED RESTS x{scale:g}, not a real run] "
    if simulator:
        prefix += "[simulator, pipeline check only] "
    print("  " + prefix + reading(cap, cold, soaked_pct, noise, probes))
    limits = ["one run", "one probe per rest"]
    if scaled:
        limits.append(f"rests scaled x{scale:g}")
    if start_state != "nominal":
        limits.append(f"started at thermal {start_state}, so the cold reference is not from a cold phone")
    if cond.get("charging"):
        limits.append("plugged in")
    if cond.get("lowPowerMode"):
        limits.append("Low Power Mode on")
    if cond.get("airplaneMode") is False:
        limits.append("network on")
    if simulator:
        limits.append("simulator CPU, not a phone GPU")
    print("  Limits: " + "; ".join(limits) + ".")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
