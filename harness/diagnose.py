#!/usr/bin/env python3
"""Read a PocketRoofline diagnostic capture and say which explanation its data fit.

The diagnostic run (matrixVersion "diag-silo-first-1") exists for one observation from the
iPhone 15 Plus session: decode stepped from 59.17 tok/s (last LISO repeat) to 29.69 tok/s (first
SILO repeat) within seconds, while prefill rose. Three explanations are open:

  H1  a power or memory state changed, and happened to coincide with the regime boundary;
  H2  decode at long context (up to 1024 tokens) is intrinsically slow on this GPU and runtime;
  H3  the app's live chart, redrawn and growing through the run, competed for the GPU.

The diagnostic runs SILO 128/1024 x 5 first, then SISO 128/128 x 3, keeps the screen still
while each repeat runs, and records the decode rate of every 64-token window. Every repeat
decodes from position 0, so its first windows are the same work in SILO and in SISO. The
predictions differ:

  H2  inside each SILO repeat the rate falls with position, even when cool, and is fast again
      when the next repeat starts back at position 0;
  H1  windows are flat inside a repeat, with a level shift between repeats (or an abrupt step
      inside one that persists);
  H3  with the screen still, the step does not appear.

Printed: each repeat's window rates; the first->last window change inside each SILO repeat; the
step between consecutive repeats; the thermal transitions; and one sentence saying which of these
predictions the data are consistent with. That sentence is a reading, never stronger than the
data: one run cannot prove a cause. With window-to-window noise above 5% there is no reading.
"Full speed" comes from this phone's own matrix v1 SISO record in results/, read only, so that a
run that is slow from the start isn't mistaken for one where the step went away.

Diagnostic captures are not matrix v1 runs. They live in results/diagnostics/, finalize.py
refuses them, and report.py and validate.py never read them.

Usage (from the repo root):
    python3 harness/diagnose.py results/diagnostics/pocketroofline-diagnostic-<unix>.json
"""
import json, pathlib, statistics as st, sys

sys.dont_write_bytecode = True  # keep harness/ free of __pycache__
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from report import spearman_index_trend  # noqa: E402

INSIDE_PCT = 10.0   # in-repeat change (first 3 vs last 3 windows): a fall at or below -10% (with rho <= -0.5), flat within +/-10%
FALL_RHO = -0.5     # ...so a single slow last window doesn't count as a fall
STEP_PCT = 20.0     # a step: an abrupt change of 20% or more that holds (median of 3 windows before vs after)
HELD = 3            # windows on each side of a boundary that a step must hold across
RESTART_PCT = 10.0  # the next repeat's first window at least 10% above this one's last: "fast again"
LEVEL_TOKENS = 128  # the level of a repeat: its rate over tokens 1-128, the same work in every repeat
NOISE_PCT = 5.0     # above this window-to-window noise, 10% falls and 20% steps can't be told from noise
FULL_SPEED = 0.8    # SILO at 80% or more of this phone's matrix v1 SISO decode: the half-speed condition is absent

RESULTS = pathlib.Path(__file__).resolve().parent.parent / "results"


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def pct(a, b):
    return (b - a) / a * 100 if a else None


def fmt_pct(x, digits=1):
    # Adding 0.0 turns a rounded -0.0 into 0.0, so nothing prints as "-0%".
    return "n/a" if x is None else f"{round(x, digits) + 0.0:+.{digits}f}%"


def thermal_note(a, b):
    return f"thermal {a} on both sides" if a == b else f"thermal {a} -> {b}"


def noise_of(silo):
    """Median, over SILO repeats, of the median absolute deviation of window-to-window changes (%).
    A steady trend changes by about the same amount each window, so it adds little; noise does."""
    per_repeat = []
    for r in silo:
        rates = [w["tokensPerSec"] for w in r["windows"]]
        changes = [pct(a, b) for a, b in zip(rates, rates[1:])]
        if len(changes) >= 3:
            mid = st.median(changes)
            per_repeat.append(st.median(abs(c - mid) for c in changes))
    return st.median(per_repeat) if per_repeat else None


def held_change(before, after):
    """Change between the medians of two runs of windows, or None if either side is too short."""
    if len(before) < 2 or len(after) < 2:
        return None
    return pct(st.median(before), st.median(after))


def level(windows, window_tokens):
    """Decode rate over the first LEVEL_TOKENS tokens, rebuilt from the windows' durations."""
    ws = [w for w in windows if w["tokensDone"] <= LEVEL_TOKENS]
    if not ws:
        return None
    seconds = sum(window_tokens / w["tokensPerSec"] for w in ws)
    return len(ws) * window_tokens / seconds


def load(path):
    try:
        cap = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        die(f"cannot read {path}: {e}")
    if cap.get("kind") != "diagnostic" or not str(cap.get("matrixVersion", "")).startswith("diag-"):
        die(f"{path} is not a diagnostic capture (kind {cap.get('kind')!r}, matrixVersion "
            f"{cap.get('matrixVersion')!r}); benchmark captures go through harness/finalize.py")
    if not cap.get("regimes"):
        die(f"{path} has no repeats")
    return cap


def reference_siso(cap):
    """This phone's matrix v1 SISO decode mean, from the run records in results/ (read only): the
    same hardware identifier, the same OS build if there is one, else the latest. Without it, the run
    has no outside measure of full speed."""
    found = []
    for p in sorted(RESULTS.glob("*.json")):
        d = json.loads(p.read_text())
        if (d.get("regime", {}).get("label") == "SISO" and d.get("matrixVersion", "v1") == "v1"
                and d.get("device", {}).get("identifier") == cap["device"].get("identifier")):
            reps = [r["decodeTokensPerSec"] for r in d["repeats"] if r.get("valid", True)]
            if reps:
                found.append({"file": p.name, "mean": st.mean(reps), "build": d["os"]["build"],
                              "capturedAt": d["capturedAt"]})
    if not found:
        return None
    found.sort(key=lambda x: (x["build"] == cap["os"].get("build"), x["capturedAt"]))
    return found[-1]


def repeats_in_order(cap, window_tokens):
    out = []
    for regime in cap["regimes"]:
        for r in regime["repeats"]:
            ws = r.get("windows", [])
            rates = [w["tokensPerSec"] for w in ws]
            first_last = pct(rates[0], rates[-1]) if len(rates) >= 2 else None
            out.append({
                "name": f"{regime['label']} {r['index'] + 1}",
                "label": regime["label"],
                "rep": r,
                "windows": ws,
                "first_last": first_last,
                # What the reading uses: medians at each end, so one odd end window can't decide it.
                "inside": held_change(rates[:HELD], rates[-HELD:]) if len(rates) >= 2 * HELD else first_last,
                "rho": spearman_index_trend(rates) if len(rates) >= 3 else None,
                "level": level(ws, window_tokens),
            })
    return out


def pairs_of(reps):
    out = []
    for a, b in zip(reps, reps[1:]):
        ar = [w["tokensPerSec"] for w in a["windows"]]
        br = [w["tokensPerSec"] for w in b["windows"]]
        out.append({
            "a": a, "b": b,
            "decode_pct": pct(a["rep"]["decodeTokensPerSec"], b["rep"]["decodeTokensPerSec"]),
            "level_pct": pct(a["level"], b["level"]) if a["level"] and b["level"] else None,
            "restart_abrupt": pct(ar[-1], br[0]) if ar and br else None,  # neighbouring windows
            "restart_pct": held_change(ar[-HELD:], br[:HELD]),            # medians either side
        })
    return out


def thermal_events(reps):
    """(seconds, where, state) for every thermal reading, in time order."""
    events = []
    for r in reps:
        rep, ws = r["rep"], r["windows"]
        events.append((rep["startSeconds"], f"{r['name']} start", rep["thermalStateStart"]))
        for i, w in enumerate(ws):
            events.append((w["secondsSinceStart"], f"{r['name']} window {i + 1} ({w['tokensDone']} tokens)",
                           w["thermalState"]))
        end = ws[-1]["secondsSinceStart"] if ws else rep["startSeconds"]
        events.append((end, f"{r['name']} end", rep["thermalStateEnd"]))
    return events


def is_step(abrupt, held):
    """Abrupt between neighbouring windows, and held: one odd window is a blip, not a step."""
    return (abrupt is not None and held is not None and abs(abrupt) >= STEP_PCT and abs(held) >= STEP_PCT
            and (abrupt > 0) == (held > 0))


def window_steps(r):
    """Steps inside one repeat, at the boundary between two neighbouring windows."""
    ws, out = r["windows"], []
    rates = [w["tokensPerSec"] for w in ws]
    for k in range(1, len(rates)):
        held = held_change(rates[max(0, k - HELD):k], rates[k:k + HELD])
        if is_step(pct(rates[k - 1], rates[k]), held):
            out.append({"pct": held, "where": f"between windows {k} and {k + 1} of {r['name']}",
                        "thermal": thermal_note(ws[k - 1]["thermalState"], ws[k]["thermalState"])})
    return out


def analyze(reps, pairs):
    """Everything the reading rests on, computed once so that the printout and the sentence agree.
    Marks each pair of consecutive repeats with "step" (True/False)."""
    silo = [r for r in reps if r["label"] == "SILO" and r["inside"] is not None]
    falls = [r for r in silo if r["inside"] <= -INSIDE_PCT and r["rho"] is not None and r["rho"] <= FALL_RHO]
    flat = [r for r in silo if abs(r["inside"]) < INSIDE_PCT]
    restarts = [p["restart_pct"] for p in pairs if p["a"]["label"] == "SILO" and p["restart_pct"] is not None]
    restart = st.median(restarts) if restarts else None
    # H2's pattern: every SILO repeat falls with position, and the next repeat starts fast again.
    position = bool(silo) and len(falls) == len(silo) and restart is not None and restart >= RESTART_PCT

    steps = [s for r in reps for s in window_steps(r)]
    for p in pairs:
        # Across a pause, compare like with like. Once position explains the falls, a restart is
        # expected to jump, so compare levels (the same work). Otherwise compare the windows either
        # side of the pause, but only after a flat repeat: after an unexplained fall, neither is clean.
        if position:
            change = p["level_pct"]
            p["step"] = change is not None and abs(change) >= STEP_PCT
        elif p["a"]["inside"] is not None and abs(p["a"]["inside"]) < INSIDE_PCT:
            change = p["restart_pct"]
            p["step"] = is_step(p["restart_abrupt"], change)
        else:
            change, p["step"] = None, False
        if p["step"]:
            steps.append({"pct": change, "where": f"between {p['a']['name']} and {p['b']['name']}",
                          "thermal": thermal_note(p["a"]["rep"]["thermalStateEnd"],
                                                  p["b"]["rep"]["thermalStateStart"])})
    return {"silo": silo, "falls": falls, "flat": flat, "restart": restart, "position": position, "steps": steps,
            "noise": noise_of(silo)}


def reading(reps, a, start_state, ref):
    """One sentence: which hypothesis the data are consistent with, and on what evidence."""
    silo, falls, flat, restart = a["silo"], a["falls"], a["flat"], a["restart"]
    if not silo:
        return "No reading: the capture has no SILO window trace."
    if a["noise"] is not None and a["noise"] > NOISE_PCT:
        return (f"No reading: the windows are too noisy (window-to-window noise {a['noise']:.1f}%, above "
                f"{NOISE_PCT:.0f}%) to tell a {INSIDE_PCT:.0f}% fall or a {STEP_PCT:.0f}% step from noise, so this "
                "run supports none of H1, H2 or H3 over the others.")
    cold = start_state == "nominal"
    cool = ", from a cold start" if cold else f"; the run started at thermal {start_state}, not cold"
    cool_h2 = cool if cold else f"; the run started at thermal {start_state}, so 'even when cool' is not tested"
    med = fmt_pct(st.median(r["inside"] for r in silo), 0)
    big = max(a["steps"], key=lambda s: abs(s["pct"])) if a["steps"] else None

    if a["position"]:
        evidence = (f"decode falls with position inside every SILO repeat (median in-repeat change {med}) and is fast "
                    f"again at each new repeat (median restart {fmt_pct(restart, 0)}), with the screen still{cool_h2}")
        if big:
            return (f"Consistent with H2, plus a step that H1 would explain: {evidence}; the "
                    f"{fmt_pct(big['pct'], 0)} step {big['where']} ({big['thermal']}) is not explained by position.")
        return f"Consistent with H2 and not with H1 or H3: {evidence}."
    if big:
        if len(flat) == len(silo):
            return (f"Consistent with H1 and not with H2: windows stay flat inside every SILO repeat (median "
                    f"in-repeat change {med}), yet the rate steps {fmt_pct(big['pct'], 0)} {big['where']} "
                    f"({big['thermal']}), with the screen still, so the live chart (H3) is not needed to produce a step.")
        return (f"Consistent with H1: the rate steps {fmt_pct(big['pct'], 0)} {big['where']} ({big['thermal']}) "
                "rather than falling steadily with position, with the screen still, so the live chart (H3) is not "
                "needed to produce a step.")
    if len(falls) == len(silo):
        return ("Not the pattern H2 predicts: decode falls inside every SILO repeat (median in-repeat change "
                f"{med}) but is not fast again when the next repeat restarts at position 0 (median restart "
                f"{fmt_pct(restart, 0)}), which reads as a slowdown carried across repeats, such as heating or a "
                "state change (H1), rather than an effect of position.")
    if len(flat) == len(silo):
        silo_dec = [r["rep"]["decodeTokensPerSec"] for r in reps if r["label"] == "SILO"]
        after = [r["rep"]["decodeTokensPerSec"] for r in reps if r["label"] != "SILO"]
        span = f"SILO decode {min(silo_dec):.1f}-{max(silo_dec):.1f} tok/s"
        if after:
            span += f", then SISO {min(after):.1f}-{max(after):.1f}"
        share = min(silo_dec) / ref["mean"] * 100 if ref else None
        if share is not None and share < FULL_SPEED * 100:
            # No step inside the run can't mean "the step went away" if the run was slow throughout.
            return (f"Consistent with H1, a state already in place, and not with H2 or H3: decode stayed flat inside "
                    f"every SILO repeat (median in-repeat change {med}) with no step ({span}), but SILO ran as low as "
                    f"{share:.0f}% of this phone's matrix v1 SISO speed of {ref['mean']:.1f} tok/s, so the slow "
                    f"condition was there from the start, with the screen still{cool}.")
        full = (f"; SILO stayed at {share:.0f}% or more of this phone's matrix v1 SISO speed of {ref['mean']:.1f} tok/s"
                if ref else "; with no matrix v1 record for this phone, whether that is full speed is not checked")
        return (f"Consistent with H3 and not with H2: with the screen still, decode stayed flat inside every SILO "
                f"repeat (median in-repeat change {med}) and no step of {STEP_PCT:.0f}% or more appeared ({span}){full}"
                f"{cool}; one run cannot rule out H1, a state change that did not recur.")
    return (f"Mixed: {len(falls)} of {len(silo)} SILO repeats fall by {INSIDE_PCT:.0f}% or more inside and "
            f"{len(flat)} stay flat, with no step of {STEP_PCT:.0f}% or more; this run does not clearly fit H1, H2 or H3.")


def main(argv):
    if argv in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if len(argv) != 1:
        print("usage: python3 harness/diagnose.py <diagnostic-capture.json>", file=sys.stderr)
        return 2
    cap = load(argv[0])
    plan = cap.get("plan", {})
    window_tokens = plan.get("windowTokens", 64)
    reps = repeats_in_order(cap, window_tokens)
    pairs = pairs_of(reps)
    analysis = analyze(reps, pairs)
    dev, os_, bk, cond = cap["device"], cap["os"], cap["backend"], cap.get("conditions", {})
    simulator = "(Simulator)" in dev.get("model", "") or bk.get("name") == "llama.cpp-cpu"
    start_state = reps[0]["rep"]["thermalStateStart"]

    print(f"PocketRoofline diagnostic {cap['matrixVersion']}: not matrix v1, never a benchmark record")
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
        seq = ", ".join(f"{b['label']} {b['promptTokens']}/{b['generateTokens']} x {b['repeats']}"
                        for b in plan.get("sequence", []))
        w = plan.get("warmup", {})
        print(f"plan: warmup {w.get('promptTokens')}/{w.get('generateTokens')}, {seq}; "
              f"{plan.get('pauseSeconds', 0):g} s pause before each repeat; {window_tokens}-token windows; "
              f"{plan.get('screen', '?')} screen")
    print(f"start: thermal {start_state}" + (" (cold start)" if start_state == "nominal" else " (not a cold start)"))
    ref = reference_siso(cap)
    if ref:
        build = "" if ref["build"] == os_["build"] else f", OS build {ref['build']}, not this run's"
        print(f"full-speed reference: this phone's matrix v1 SISO decode mean {ref['mean']:.2f} tok/s "
              f"(results/{ref['file']}{build})")
    else:
        print("full-speed reference: none (no matrix v1 SISO record for this hardware identifier in results/)")
    if simulator:
        print("NOTE: simulator capture (llama.cpp on the Mac's CPU). It checks the pipeline only and says "
              "nothing about any phone.")

    print(f"\nPer repeat, in run order. tok/s; t = seconds since the first repeat began; windows = each "
          f"{window_tokens}-token window in order.")
    for r in reps:
        rep = r["rep"]
        print(f"  {r['name']:<7} t={rep['startSeconds']:6.1f}  decode {rep['decodeTokensPerSec']:6.2f}  "
              f"prefill {rep['prefillTokensPerSec']:6.1f}  thermal {rep['thermalStateStart']} -> "
              f"{rep['thermalStateEnd']}")
        print("          windows " + (" ".join(f"{w['tokensPerSec']:.1f}" for w in r["windows"]) or "(none)"))
        if r["label"] == "SILO" and r["inside"] is not None:
            rho = "n/a" if r["rho"] is None else f"{r['rho']:+.2f}"
            print(f"          first->last window {fmt_pct(r['first_last'])}  (first {HELD} vs last {HELD}: "
                  f"{fmt_pct(r['inside'])}, rho {rho})")
        steps = window_steps(r)
        if steps:
            big = max(steps, key=lambda s: abs(s["pct"]))
            more = f" (largest of {len(steps)})" if len(steps) > 1 else ""
            print(f"          step {fmt_pct(big['pct'])} {big['where']}, {big['thermal']}{more}")

    print(f"\nBetween consecutive repeats. level = rate over tokens 1-{LEVEL_TOKENS}, the same work in every "
          f"repeat; restart = next repeat's first {HELD} windows vs this one's last {HELD} (medians).")
    for p in pairs:
        a, b = p["a"], p["b"]
        lv = (f"level {a['level']:.1f} -> {b['level']:.1f} ({fmt_pct(p['level_pct'])})"
              if a["level"] and b["level"] else "level n/a")
        flag = "  <- step" if p["step"] else ""
        print(f"  {a['name']:<7} -> {b['name']:<7} decode {a['rep']['decodeTokensPerSec']:6.2f} -> "
              f"{b['rep']['decodeTokensPerSec']:6.2f} ({fmt_pct(p['decode_pct'])})  {lv}  "
              f"restart {fmt_pct(p['restart_pct'])}{flag}")

    print("\nThermal transitions:")
    events = thermal_events(reps)
    changes = [(t, where, prev, now) for (_, _, prev), (t, where, now) in zip(events, events[1:]) if now != prev]
    for t, where, prev, now in changes:
        print(f"  t={t:6.1f}  {where}: {prev} -> {now}")
    if not changes:
        print(f"  none: {start_state} throughout")

    noise = analysis["noise"]
    print(f"\nWindow-to-window noise inside SILO repeats: "
          + ("n/a" if noise is None else f"{noise:.1f}% (median absolute deviation of the changes; a steady "
                                          "trend adds little)"))

    print(f"\nReading. The in-repeat change compares a SILO repeat's first {HELD} windows with its last {HELD} "
          f"(medians): a fall is <= -{INSIDE_PCT:.0f}% with rho <= {FALL_RHO}, and flat is within "
          f"+/-{INSIDE_PCT:.0f}%. A step is a change of {STEP_PCT:.0f}% or more between "
          f"neighbouring windows that holds over {HELD} windows each side (across a pause, only after a flat "
          f"repeat), or between consecutive repeats' levels once every SILO repeat falls and restarts at least "
          f"{RESTART_PCT:.0f}% faster. Above {NOISE_PCT:.0f}% noise there is no reading. Without a step, H3 also "
          f"needs SILO at {FULL_SPEED * 100:.0f}% or more of the full-speed reference.")
    print(("  [simulator, pipeline check only] " if simulator else "  ") + reading(reps, analysis, start_state, ref))
    limits = ["one run"]
    if start_state != "nominal":
        limits.append(f"started at thermal {start_state}, not cold")
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
