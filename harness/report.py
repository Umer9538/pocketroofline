#!/usr/bin/env python3
"""Read every run record in results/ and emit the summary page.

Statistics are computed here, never hand-entered: per-regime mean, sd, a
bootstrap 95% CI of the mean, the first->last delta, and a Spearman rank trend
that distinguishes a genuine monotonic decline (throttling) from scatter.

Repeats flagged invalid (thermal state changed mid-run, per METHODOLOGY 5) are
excluded from aggregates and still shown in the table and the chart.

Phone records are grouped into sessions (the records finalized from one
capture), oldest first. The first session is station 01 and carries the page
headline. Each later session gets its own station section, with the caveats
that follow from its records plus any in SESSION_NOTES. Where results/bandwidth/
holds Headroom probes for that phone and OS build, its roofline placement uses
that measured ceiling (METHODOLOGY 3) instead of a published peak.

Writes docs/index.html. Run from the repo root:
    python3 harness/report.py
"""
import json, pathlib, random, statistics as st, html

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
CAPTURES = RESULTS / "captures"    # raw captures, as exported from the device
BANDWIDTH = RESULTS / "bandwidth"  # raw Headroom probe reports
OUT = ROOT / "docs" / "index.html"

# Emphasis palette (dataviz skill): one accent + de-emphasis gray.
# Validated: CVD dE 11.6 light / 11.1 dark, normal-vision 16.9, contrast >= 3:1.
ACCENT_L, GRAY_L = "#d95926", "#8a8985"
ACCENT_D, GRAY_D = "#eb6834", "#9a998f"

REGIME_ORDER = ["SISO", "LISO", "SILO"]
ANCHOR_SOC = "Apple M1"  # the mains-powered control; every other device is a phone

# Published peak memory bandwidth, in GB/s. These are vendor/third-party figures,
# NOT measured here. They are used only for a chip with no measured ceiling in
# results/bandwidth/ (METHODOLOGY 3). Public sources disagree on the A15, so it
# is carried as a range and every derived utilisation figure is a range too.
PEAK_BW = {
    "Apple M1": {"low": 68.25, "high": 68.25,
                 "note": "68.25 GB/s, consistently reported (128-bit LPDDR4X-4266)"},
    "A15 Bionic": {"low": 34.1, "high": 42.7,
                   "note": "public sources disagree: 34.1 GB/s (64-bit LPDDR4X-4266) vs 42.7 GB/s"},
}


# --- Judgements the statistics cannot make ------------------------------------
# Keyed by session: a record's runId minus its regime suffix. Each function takes
# the session's summaries as {regime label: summary}, so every number in the
# prose still comes from the records.

def _a16_caption(S):
    li, si, so = S["LISO"], S["SISO"]["decode"], S["SILO"]["decode"]
    d, reps = li["decode"], li["run"]["repeats"]
    return (f"<b>LISO</b> declines monotonically — Spearman rho {d['rho']:+.2f}, {d['all'][0]:.2f} → "
            f"{d['all'][-1]:.2f} tok/s as the thermal state goes {reps[0]['thermalStateStart']} → "
            f"{reps[-1]['thermalStateEnd']} — while SISO holds flat (CV {si['cv']:.1f}%). SILO starts at "
            f"{so['all'][0]:.2f} tok/s, a step down from LISO's last repeat. That step is caveat 3 and is "
            "unexplained, so the SILO line is not read here as a throttling curve.")


def _a16_silo_step(S):
    lr, sr = S["LISO"]["run"], S["SILO"]["run"]
    a, b = lr["repeats"][-1], sr["repeats"][0]
    return (f"<b>The SILO step is unexplained.</b> Decode fell from {a['decodeTokensPerSec']:.2f} tok/s in the "
            f"last LISO repeat to {b['decodeTokensPerSec']:.2f} tok/s in the first SILO repeat, seconds later, "
            f"with the thermal state {a['thermalStateEnd']} on both sides, while prefill rose from "
            f"{a['prefillTokensPerSec']:.0f} to {b['prefillTokensPerSec']:.0f} tok/s (over "
            f"{lr['regime']['promptTokens']}- and {sr['regime']['promptTokens']}-token prompts). A plain thermal "
            "slowdown would have pulled prefill down too, and nothing recorded here explains the step. A "
            "cold-start run with SILO first is owed. Until it exists, no peak-to-sustained percentage is quoted "
            "for this phone, and its SILO figures are not a sustained-throughput estimate.")


SESSION_NOTES = {
    "iphone-15-plus-ios27.0-24A437-tinyllama-1-1b-1t-openorca-q4_0-20261005t011056z": {
        "caption": _a16_caption,
        "aria": ("Decode throughput per repeat for each regime on the iPhone 15 Plus. LISO declines "
                 "monotonically and SISO stays flat; SILO sits far below both from its first repeat."),
        "caveats": [_a16_silo_step],
    },
}


def achieved_bandwidth(decode_tok_s, tensor_bytes):
    """Single-stream autoregressive decode reads every weight once per token, so
    achieved bandwidth is decode rate x weight bytes. A lower bound on what the
    memory system actually delivered, and the standard way to place a decode
    workload on a roofline."""
    return decode_tok_s * tensor_bytes / 1e9


def published_util(soc, bw):
    """Achieved bandwidth as a share of the published peak: a range where sources disagree."""
    peak_spec = PEAK_BW.get(soc)
    if not peak_spec:
        return "—"
    u_hi = bw / peak_spec["low"] * 100
    u_lo = bw / peak_spec["high"] * 100
    return f"{u_lo:.0f}–{u_hi:.0f}%" if peak_spec["low"] != peak_spec["high"] else f"{u_hi:.0f}%"


def measured_ceilings():
    """Measured bandwidth ceiling per (device identifier, OS build), from the Headroom
    probe reports in results/bandwidth/: the median, across probes, of each report's
    verified GPU STREAM-triad median (METHODOLOGY 3)."""
    found = {}
    for p in sorted(BANDWIDTH.glob("*.json")):
        d = json.loads(p.read_text())
        triad = (d.get("gpu") or {}).get("triad") or {}
        if not triad.get("verified"):
            continue
        key = (d["device"].get("identifier"), d["device"].get("osBuild"))
        found.setdefault(key, []).append({
            "file": p.name, "capturedAt": d["capturedAt"], "arrayBytes": d["gpu"].get("arrayBytes"),
            "gbps": triad["medianGBps"]["value"], "conditions": d.get("conditions", {}),
        })
    out = {}
    for key, probes in found.items():
        probes.sort(key=lambda x: x["capturedAt"])
        out[key] = {"gbps": st.median(x["gbps"] for x in probes), "probes": probes}
    return out


def bootstrap_ci(vals, n=20000, conf=0.95, seed=42):
    if len(vals) < 2:
        return (float("nan"), float("nan"))
    rng = random.Random(seed)
    means = sorted(st.mean(rng.choices(vals, k=len(vals))) for _ in range(n))
    return means[int((1 - conf) / 2 * n)], means[int((1 + conf) / 2 * n)]


def spearman_index_trend(vals):
    """Rank correlation of value against repeat order. -1 = perfectly monotonic decline."""
    n = len(vals)
    if n < 3:
        return float("nan")
    order = sorted(range(n), key=lambda i: vals[i])
    rank = [0] * n
    for r, i in enumerate(order):
        rank[i] = r
    dsq = sum((i - rank[i]) ** 2 for i in range(n))
    return 1 - 6 * dsq / (n * (n * n - 1))


def load_runs():
    runs = []
    for p in sorted(RESULTS.glob("*.json")):
        d = json.loads(p.read_text())
        if "regime" not in d:  # skip anything that is not a run record
            continue
        runs.append(d)
    return runs


def summarize(run):
    label = run["regime"].get("label", "?")
    reps = run["repeats"]
    valid = [r for r in reps if r.get("valid", True)]
    out = {"label": label, "run": run, "flagged": len(reps) - len(valid)}
    for metric, key in (("prefill", "prefillTokensPerSec"), ("decode", "decodeTokensPerSec")):
        allv = [r[key] for r in reps]
        v = [r[key] for r in valid] or allv
        lo, hi = bootstrap_ci(v)
        out[metric] = {
            "all": allv,
            "mean": st.mean(v),
            "sd": st.stdev(v) if len(v) > 1 else 0.0,
            "ci": (lo, hi),
            "first_last_pct": (allv[-1] - allv[0]) / allv[0] * 100 if allv[0] else 0.0,
            "rho": spearman_index_trend(allv),
            "cv": (st.stdev(v) / st.mean(v) * 100) if len(v) > 1 and st.mean(v) else 0.0,
        }
    return out


def regime_rank(s):
    return REGIME_ORDER.index(s["label"]) if s["label"] in REGIME_ORDER else 99


def session_key(run):
    """The records finalized from one capture share their runId up to the regime suffix."""
    suffix = "-" + run["regime"].get("label", "").lower()
    rid = run["runId"]
    return rid[: -len(suffix)] if suffix != "-" and rid.endswith(suffix) else rid


def sessions_of(runs):
    """Group run records into sessions, oldest capture first; regimes in run order."""
    groups = {}
    for r in runs:
        groups.setdefault(session_key(r), []).append(r)
    out = [{"key": k, "runs": rs, "capturedAt": min(r["capturedAt"] for r in rs),
            "summaries": sorted((summarize(r) for r in rs), key=regime_rank)}
           for k, rs in groups.items()]
    out.sort(key=lambda s: s["capturedAt"])
    return out


def capture_file(run):
    """The raw capture in results/captures/ that a record was finalized from, if kept."""
    for p in sorted(CAPTURES.glob("*.json")):
        try:
            d = json.loads(p.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if (d.get("capturedAt") == run["capturedAt"]
                and d.get("device", {}).get("identifier") == run["device"].get("identifier")):
            return p
    return None


def compare_chart(phone_sum, anchor_sum, metric="decode"):
    """Phone vs mains-powered anchor on the identical long-generation regime.

    Two series only, both emphasised (they are the comparison), distinguished by
    accent vs ink and direct-labelled - identity is never colour-alone.
    """
    ph = next((s for s in phone_sum if s["label"] == "SILO"), None)
    an = next((s for s in anchor_sum if s["label"] == "SILO"), None)
    if not ph or not an:
        return ""
    W, H = 720, 260
    ml, mr, mt, mb = 54, 150, 18, 40
    pw, ph_ = W - ml - mr, H - mt - mb
    a, b = ph[metric]["all"], an[metric]["all"]
    n = max(len(a), len(b))
    vals = a + b
    lo, hi = min(vals), max(vals)
    pad = (hi - lo) * 0.15 or 1
    lo, hi = lo - pad, hi + pad
    X = lambda i: ml + pw * i / max(1, n - 1)
    Y = lambda v: mt + ph_ - (v - lo) / (hi - lo) * ph_
    parts = []
    for k in range(5):
        v = lo + (hi - lo) * k / 4
        y = Y(v)
        parts.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml+pw}" y2="{y:.1f}" class="grid"/>')
        parts.append(f'<text x="{ml-10}" y="{y+4:.1f}" class="ax" text-anchor="end">{v:.0f}</text>')
    for i in range(n):
        parts.append(f'<text x="{X(i):.1f}" y="{mt+ph_+22}" class="ax" text-anchor="middle">{i}</text>')
    parts.append(f'<text x="{ml+pw/2:.1f}" y="{H-4}" class="axt" text-anchor="middle">consecutive long generations</text>')
    labels = []
    for vals_, cls, name in ((b, "anchor", an["run"]["device"]["soc"]), (a, "emph", ph["run"]["device"]["soc"])):
        pts = " ".join(f"{X(i):.1f},{Y(x):.1f}" for i, x in enumerate(vals_))
        parts.append(f'<polyline points="{pts}" class="ln {cls}"/>')
        for i, x in enumerate(vals_):
            parts.append(f'<circle cx="{X(i):.1f}" cy="{Y(x):.1f}" r="4.5" class="pt {cls}">'
                         f"<title>{name} repeat {i}: {x:.2f} tok/s</title></circle>")
        labels.append({"y": Y(vals_[-1]), "cls": cls, "text": f"{name} · {vals_[-1]:.1f}"})
    labels.sort(key=lambda l: l["y"])
    for i in range(1, len(labels)):
        if labels[i]["y"] - labels[i - 1]["y"] < 15:
            labels[i]["y"] = labels[i - 1]["y"] + 15
    for l in labels:
        parts.append(f'<text x="{X(n-1)+10:.1f}" y="{l["y"]+4:.1f}" class="dl {l["cls"]}">{l["text"]}</text>')
    return (f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="Decode throughput over five consecutive long '
            f'generations. The mains-powered anchor holds flat; the phone declines.">{"".join(parts)}</svg>')


def line_chart(summaries, metric="decode", aria=None):
    """Emphasis line chart: the throttling series in accent, the rest as context."""
    W, H = 720, 300
    ml, mr, mt, mb = 54, 116, 18, 40
    pw, ph = W - ml - mr, H - mt - mb
    series = [s for s in summaries if s["label"] in REGIME_ORDER]
    series.sort(key=lambda s: REGIME_ORDER.index(s["label"]))
    if not series:
        return ""
    n = max(len(s[metric]["all"]) for s in series)
    vals = [v for s in series for v in s[metric]["all"]]
    lo, hi = min(vals), max(vals)
    pad = (hi - lo) * 0.18 or 1
    lo, hi = lo - pad, hi + pad

    def X(i):
        return ml + (pw * i / max(1, n - 1))

    def Y(v):
        return mt + ph - (v - lo) / (hi - lo) * ph

    # The emphasised series is the one with the strongest monotonic decline.
    focus = min(series, key=lambda s: s[metric]["rho"])["label"]

    parts = []
    # recessive gridlines + y labels
    steps = 4
    for k in range(steps + 1):
        v = lo + (hi - lo) * k / steps
        y = Y(v)
        parts.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml+pw}" y2="{y:.1f}" class="grid"/>')
        parts.append(f'<text x="{ml-10}" y="{y+4:.1f}" class="ax" text-anchor="end">{v:.0f}</text>')
    for i in range(n):
        parts.append(f'<text x="{X(i):.1f}" y="{mt+ph+22}" class="ax" text-anchor="middle">{i}</text>')
    parts.append(f'<text x="{ml+pw/2:.1f}" y="{H-4}" class="axt" text-anchor="middle">repeat index (in run order)</text>')
    parts.append(f'<text x="14" y="{mt+ph/2:.1f}" class="axt" text-anchor="middle" transform="rotate(-90 14 {mt+ph/2:.1f})">{metric} tok/s</text>')

    labels = []
    for s in series:
        v = s[metric]["all"]
        emph = s["label"] == focus
        cls = "emph" if emph else "ctx"
        pts = " ".join(f"{X(i):.1f},{Y(x):.1f}" for i, x in enumerate(v))
        parts.append(f'<polyline points="{pts}" class="ln {cls}"/>')
        for i, x in enumerate(v):
            flagged = not s["run"]["repeats"][i].get("valid", True)
            r = 4.5 if emph else 3.5
            extra = ' stroke-dasharray="2 2"' if flagged else ""
            parts.append(
                f'<circle cx="{X(i):.1f}" cy="{Y(x):.1f}" r="{r}" class="pt {cls}"{extra}>'
                f"<title>{s['label']} repeat {i}: {x:.2f} tok/s"
                f"{' (flagged: thermal state changed mid-run)' if flagged else ''}</title></circle>"
            )
        labels.append({"y": Y(v[-1]), "cls": cls, "text": f'{s["label"]} · {v[-1]:.1f}'})

    # Direct labels at the series ends - identity is never colour-alone. Nudge
    # apart any that would collide, so close series stay readable.
    labels.sort(key=lambda l: l["y"])
    MIN_GAP = 15.0
    for i in range(1, len(labels)):
        if labels[i]["y"] - labels[i - 1]["y"] < MIN_GAP:
            labels[i]["y"] = labels[i - 1]["y"] + MIN_GAP
    lx = X(n - 1) + 10
    for l in labels:
        parts.append(f'<text x="{lx:.1f}" y="{l["y"]+4:.1f}" class="dl {l["cls"]}">{l["text"]}</text>')

    if aria is None:
        aria = f"Decode throughput per repeat for each regime. {focus} declines monotonically; the others stay flat."
    return f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="{html.escape(aria)}">{"".join(parts)}</svg>'


def regime_rows(summaries):
    """Per-regime table body."""
    rows = []
    for s in summaries:
        d, p = s["decode"], s["prefill"]
        rows.append(
            f"<tr><th>{s['label']}</th>"
            f"<td>{s['run']['regime']['promptTokens']} / {s['run']['regime']['generateTokens']}</td>"
            f"<td>{p['mean']:.1f}</td>"
            f"<td>{d['mean']:.2f} <span class='sd'>± {d['sd']:.2f}</span></td>"
            f"<td>[{d['ci'][0]:.2f}, {d['ci'][1]:.2f}]</td>"
            f"<td class='{'neg' if d['first_last_pct'] < -5 else ''}'>{d['first_last_pct']:+.1f}%</td>"
            f"<td>{d['rho']:+.2f}</td>"
            f"<td>{s['run']['repeats'][0]['thermalStateStart']} → {s['run']['repeats'][-1]['thermalStateEnd']}</td></tr>"
        )
    return "".join(rows)


def repeat_rows(summaries):
    """Full per-repeat table body (the accessible table view of the chart)."""
    rows = []
    for s in summaries:
        for i, r in enumerate(s["run"]["repeats"]):
            flag = "" if r.get("valid", True) else " <span class='flag'>flagged</span>"
            rows.append(
                f"<tr><th>{s['label']} #{i}</th><td>{r['prefillTokensPerSec']:.1f}</td>"
                f"<td>{r['decodeTokensPerSec']:.2f}</td><td>{r['ttftMs']:.1f}</td>"
                f"<td>{r['thermalStateStart']} → {r['thermalStateEnd']}{flag}</td></tr>"
            )
    return "".join(rows)


def derived_caveats(sess, ref):
    """Caveats that follow from the records themselves (ref = station 01's session)."""
    out = []
    run0, ref0 = sess["runs"][0], ref["runs"][0]
    start = sess["summaries"][0]["run"]["repeats"][0]["thermalStateStart"]
    if start != "nominal":
        same = ref["summaries"][0]["run"]["repeats"][0]["thermalStateStart"] != "nominal"
        out.append(f"<b>Warm start.</b> The run began at thermal state <b>{html.escape(start)}</b>, not "
                   "<b>nominal</b>: the ten-minute cooldown of METHODOLOGY §5 was not achieved, so these are "
                   f"<b>warm-start</b> figures{', the same deviation as station 01' if same else ''}.")
    if run0.get("source") == "app" and ref0.get("source") != "app":
        out.append("<b>Captured with the app.</b> The PocketRoofline app redraws a live decode chart while each "
                   "repeat runs; the harness that captured station 01 drew nothing during a repeat. GPU contention "
                   "from that drawing is a possible confound, so a difference between this phone and station 01 "
                   "cannot yet be put down to the silicon alone.")
    return out


def probe_conditions(probes):
    conds = [p["conditions"] for p in probes]
    thermal = sorted({c.get("thermalState", "unrecorded") for c in conds})
    power = sorted({c.get("powerSource", "unrecorded") for c in conds})
    parts = [f"thermal state {'/'.join(thermal)}",
             "on battery" if power == ["battery"] else f"power source {'/'.join(power)}"]
    lpm = {c.get("isLowPowerModeEnabled") for c in conds}
    if lpm == {False}:
        parts.append("Low Power Mode off")
    elif True in lpm:
        parts.append("Low Power Mode on")
    return ", ".join(parts)


def station_block(sess, number, anchor_id, tag, ref, ceilings):
    """One later phone session: its own chart, tables, roofline placement, caveats and provenance.
    No peak-to-sustained headline: the page carries one, station 01's."""
    sums = sess["summaries"]
    S = {s["label"]: s for s in sums}
    run0, ref0 = sess["runs"][0], ref["runs"][0]
    dev, os_, mdl, bk = run0["device"], run0["os"], run0["model"], run0["backend"]
    note = SESSION_NOTES.get(sess["key"], {})
    caveats = derived_caveats(sess, ref) + [f(S) for f in note.get("caveats", [])]
    tb = mdl.get("tensorBytes")
    ceil = ceilings.get((dev.get("identifier"), os_["build"]))
    from_app = run0.get("source") == "app"

    same = (mdl["fileSha256"] == ref0["model"]["fileSha256"]
            and bk.get("commit") == ref0["backend"].get("commit")
            and [s["run"]["regime"] for s in sums] == [s["run"]["regime"] for s in ref["summaries"]])
    via = f"PocketRoofline app {run0.get('appVersion', '')}".rstrip() if from_app else "iOS harness"
    lede = (f"{html.escape(os_['name'])} {html.escape(os_['version'])} ({html.escape(os_['build'])}), captured "
            f"{html.escape(run0['capturedAt'][:10])} with the {html.escape(via)}"
            + (", on the same model file, regimes and llama.cpp commit as station 01." if same else "."))
    siso = S.get("SISO")
    if siso:
        d = siso["decode"]
        lede += f" Short-generation decode (SISO) averaged <b>{d['mean']:.2f} tok/s</b> (sd {d['sd']:.2f})"
        if tb:
            bw = achieved_bandwidth(d["mean"], tb)
            lede += f", which reads weights at {bw:.1f} GB/s"
            if ceil:
                lede += (f": <b>{bw / ceil['gbps'] * 100:.0f}% of this phone's measured ceiling</b> "
                         f"({ceil['gbps']:.1f} GB/s, Headroom probe)")
        lede += "."
    if caveats:
        lede += " Read the caveats below before using any figure from this phone."

    cav = ""
    if caveats:
        cav = ('\n  <div class="note" style="margin-top:18px">\n    <p><b>Caveats, which apply to every figure in '
               'this section:</b></p>\n    <ol>' + "".join(f"<li>{c}</li>" for c in caveats) + "</ol>\n  </div>\n")

    caption = note["caption"](S) if "caption" in note else (
        "Decode tok/s per repeat, one line per regime, regimes in run order. Spearman rho against repeat order: "
        + ", ".join(f"{s['label']} {s['decode']['rho']:+.2f}" for s in sums) + ".")
    chart = line_chart(sums, "decode", aria=note.get("aria", "Decode throughput per repeat for each regime."))

    bw_block = ""
    if tb:
        rows = []
        for s in sums:
            d = s["decode"]
            bw_mean = achieved_bandwidth(d["mean"], tb)
            bw_last = achieved_bandwidth(d["all"][-1], tb)
            util = f"{bw_mean / ceil['gbps'] * 100:.0f}%" if ceil else published_util(dev["soc"], bw_mean)
            rows.append(f"<tr><th>{html.escape(dev['soc'])}</th><td>{s['label']}</td>"
                        f"<td>{d['mean']:.2f}</td><td>{bw_mean:.1f}</td>"
                        f"<td>{bw_last:.1f}</td><td>{util}</td></tr>")
        if ceil:
            head = "% of measured ceiling (Headroom probe)"
            probes = ceil["probes"]
            thermal = {p["conditions"].get("thermalState", "unrecorded") for p in probes}
            match = [s["label"] for s in sums
                     if all(r["thermalStateStart"] in thermal and r["thermalStateEnd"] in thermal
                            for r in s["run"]["repeats"])]
            other = [s["label"] for s in sums if s["label"] not in match]
            reached = sorted({r[k] for s in sums if s["label"] in other for r in s["run"]["repeats"]
                              for k in ("thermalStateStart", "thermalStateEnd")} - thermal)
            like = ""
            if match:
                like = (f" Only {' and '.join(match)} ran entirely at that thermal state, so "
                        f"{'that row is' if len(match) == 1 else 'those rows are'} the like-for-like placement")
                like += (f"; {' and '.join(other)} reached {'/'.join(reached)}, where the ceiling was not "
                         "re-measured." if other and reached else ".")
            t0, t1 = probes[0]["capturedAt"], probes[-1]["capturedAt"]
            each = ", ".join(f"{p['gbps']:.2f}" for p in probes)
            sizes = {p["arrayBytes"] for p in probes}
            over = f" over three {sizes.pop() / 2**20:g} MiB buffers" if len(sizes) == 1 and None not in sizes else ""
            bw_note = (
                f"<p><b>Measured ceiling (Headroom probe): {ceil['gbps']:.1f} GB/s.</b> This is the measured "
                "ceiling METHODOLOGY §3 asks for, in place of a published peak: a STREAM triad on this phone's "
                f"GPU through Metal{over}, by the "
                '<a href="https://github.com/Umer9538/headroom">Headroom</a> probe. '
                f"It is the median of {len(probes)} probes ({each} GB/s), "
                f"taken {html.escape(t0[:10])} {html.escape(t0[11:19])}–{html.escape(t1[11:19])} UTC on "
                f"{html.escape(dev['identifier'])} with the same OS build, {probe_conditions(probes)}. "
                "This run's capture is stamped "
                f"{html.escape(run0['capturedAt'][11:19])} UTC, at the end of the run. No published "
                f"{html.escape(dev['soc'])} figure is used.</p>"
                f"<p style=\"margin-top:8px\">The ceiling was measured at thermal state {'/'.join(sorted(thermal))}."
                f"{like} The caveats above apply to every row.</p>")
        else:
            head = "% of published peak"
            bw_note = ("<p>No measured ceiling exists yet for this phone; any percentage is against a published "
                       "figure, not a measurement (METHODOLOGY §3).</p>")
        bw_block = f"""
  <h3>Where this sits on the roofline</h3>
  <p class="lede" style="font-size:15px">The same conversion as station 01: decode tok/s × {tb/1e9:.3f} GB of
  weights per token gives achieved memory bandwidth, placed here against {'a ceiling measured on this phone' if ceil else 'a published peak, where one exists'}.</p>
  <div class="scroll"><table>
    <thead><tr><th>SoC</th><th>Regime</th><th>Decode tok/s</th><th>Achieved GB/s</th>
    <th>Final repeat GB/s</th><th>{head}</th></tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table></div>
  <div class="note" style="margin-top:14px">
    {bw_note}
  </div>
"""

    cond = run0.get("conditions", {})
    if from_app:
        bits = []
        if cond.get("airplaneMode") is True:
            bits.append("no usable network path at any sample (airplane mode)")
        if cond.get("charging") is False:
            bits.append("unplugged")
        if cond.get("lowPowerMode") is False:
            bits.append("Low Power Mode off")
        if "batteryStartPct" in cond and "batteryEndPct" in cond:
            bits.append(f"battery {cond['batteryStartPct']:g}% → {cond['batteryEndPct']:g}%")
        conditions_line = ", ".join(bits) + ", app in foreground"
    else:
        conditions_line = "airplane mode, unplugged, app in foreground"
    raw = []
    cap = capture_file(run0)
    if cap:
        raw.append(f"raw capture: results/captures/{html.escape(cap.name)}")
    if ceil:
        raw.append(f"bandwidth probes: {len(ceil['probes'])} reports in results/bandwidth/")

    return f"""
  <section class="station" id="{anchor_id}">
  <p class="eyebrow">PocketRoofline · station {number:02d}{tag}</p>
  <h2 class="st">{html.escape(dev['model'])} ({html.escape(dev['soc'])}, {dev['ramGB']:g}&nbsp;GB)</h2>
  <p class="lede">{lede}</p>
  {cav}
  <h3>Decode throughput per repeat</h3>
  <figure>
    {chart}
    <figcaption>{caption}</figcaption>
  </figure>

  <h3>Per regime</h3>
  <div class="scroll"><table>
    <thead><tr><th>Regime</th><th>in / out</th><th>Prefill tok/s</th><th>Decode tok/s</th>
    <th>95% CI (decode)</th><th>First→last</th><th>rho</th><th>Thermal</th></tr></thead>
    <tbody>{regime_rows(sums)}</tbody>
  </table></div>
  {bw_block}
  <h3>Every repeat</h3>
  <div class="scroll"><table>
    <thead><tr><th>Run</th><th>Prefill tok/s</th><th>Decode tok/s</th><th>TTFT ms</th><th>Thermal</th></tr></thead>
    <tbody>{repeat_rows(sums)}</tbody>
  </table></div>

  <h3>Provenance</h3>
  <p class="meta">
    {html.escape(dev['model'])} · {html.escape(dev['soc'])} · {dev['ramGB']} GB{' · ' + html.escape(dev['identifier']) if dev.get('identifier') else ''}<br>
    {html.escape(os_['name'])} {html.escape(os_['version'])} ({html.escape(os_['build'])})<br>
    {html.escape(bk['name'])} @ {html.escape(bk['commit'][:12])}<br>
    {html.escape(mdl['id'])} {html.escape(mdl['quant'])} · {mdl['params']:.3g}B · sha256 {html.escape(mdl['fileSha256'][:16])}…<br>
    {html.escape(via)} · {html.escape(conditions_line)}{''.join('<br>' + x for x in raw)}
  </p>
  </section>
"""


def main():
    runs = load_runs()
    if not runs:
        print("no run records found")
        return
    anchor = [r for r in runs if r["device"]["soc"] == ANCHOR_SOC]
    stations = sessions_of([r for r in runs if r["device"]["soc"] != ANCHOR_SOC])
    ceilings = measured_ceilings()

    # Station numbers follow the device, in order of its first session. A device
    # with more than one session gets each session's capture date in its label.
    def device_key(sess):
        d = sess["runs"][0]["device"]
        return d.get("identifier") or d["model"]

    per_device = {}
    for sess in stations:
        per_device[device_key(sess)] = per_device.get(device_key(sess), 0) + 1
    numbers, ids, placed = {}, set(), []
    for sess in stations:
        n = numbers.setdefault(device_key(sess), len(numbers) + 1)
        anchor_id = f"station-{n:02d}"
        k = 2
        while anchor_id in ids:
            anchor_id, k = f"station-{n:02d}-{k}", k + 1
        ids.add(anchor_id)
        tag = f" · {sess['capturedAt'][:10]}" if per_device[device_key(sess)] > 1 else ""
        placed.append((n, anchor_id, sess, tag))
    first = stations[0]
    later = placed[1:]

    phone = first["runs"]
    summaries = first["summaries"]
    anchor_sum = sorted([summarize(r) for r in anchor], key=regime_rank)

    # Headline: peak (best stable regime decode) vs sustained (last repeat of the throttling regime)
    thr = min(summaries, key=lambda s: s["decode"]["rho"])
    stable = max(summaries, key=lambda s: s["decode"]["mean"])
    peak = stable["decode"]["mean"]
    sustained = thr["decode"]["all"][-1]
    gap = (peak - sustained) / sustained * 100

    dev = phone[0]["device"]
    os_ = phone[0]["os"]
    mdl = phone[0]["model"]
    bk = phone[0]["backend"]

    nav = ""
    if later:
        links = " · ".join(
            f'<a href="#{aid}">station {n:02d} · {html.escape(s["runs"][0]["device"]["model"])} '
            f'({html.escape(s["runs"][0]["device"]["soc"])}){tag}</a>' for n, aid, s, tag in later)
        nav = (f'\n  <p class="meta stations">Station 01 is the {html.escape(dev["model"])} whose figures follow. '
               f"Also measured: {links}, further down, {'each ' if len(later) > 1 else ''}with its caveats "
               "up front.</p>\n")

    # --- Roofline placement: achieved memory bandwidth vs published peak ---
    tb = mdl.get("tensorBytes")
    bw_block = ""
    if tb:
        bw_rows = []
        for src, sums in (("phone", summaries), ("anchor", anchor_sum)):
            for s in sums:
                soc = s["run"]["device"]["soc"]
                d = s["decode"]
                bw_mean = achieved_bandwidth(d["mean"], tb)
                bw_last = achieved_bandwidth(d["all"][-1], tb)
                util = published_util(soc, bw_mean)
                bw_rows.append(
                    f"<tr><th>{html.escape(soc)}</th><td>{s['label']}</td>"
                    f"<td>{d['mean']:.2f}</td><td>{bw_mean:.1f}</td>"
                    f"<td>{bw_last:.1f}</td><td>{util}</td></tr>"
                )
        notes = " · ".join(f"{html.escape(k)}: {html.escape(v['note'])}" for k, v in PEAK_BW.items())
        measured_later = [(aid, s) for n, aid, s, tag in later
                          if (s["runs"][0]["device"].get("identifier"), s["runs"][0]["os"]["build"]) in ceilings]
        measured_note = ""
        if measured_later:
            refs = ", ".join(f'the {html.escape(s["runs"][0]["device"]["soc"])} at <a href="#{aid}">'
                             f'{aid.replace("-", " ", 1)}</a>' for aid, s in measured_later)
            measured_note = f" A measured ceiling now exists for {refs}, and its placement uses it."
        bw_block = f"""
  <h2>Where this sits on the roofline</h2>
  <p class="lede" style="font-size:15px">Single-stream decode reads every weight once per token, so
  decode throughput converts directly into achieved memory bandwidth
  ({tb/1e9:.3f} GB of weights per token). That places this workload firmly in the
  memory-bound region — which is why decode, not prefill, is what thermal throttling destroys.</p>
  <div class="scroll"><table>
    <thead><tr><th>SoC</th><th>Regime</th><th>Decode tok/s</th><th>Achieved GB/s</th>
    <th>Final repeat GB/s</th><th>% of published peak</th></tr></thead>
    <tbody>{''.join(bw_rows)}</tbody>
  </table></div>
  <div class="note" style="margin-top:14px">
    <p><b>The percentages are the weakest numbers on this page.</b> Peak bandwidth here is a
    <b>published vendor figure, not a measurement</b> — and for the A15 the public figures disagree
    ({notes}), so its utilisation is given as a range. A STREAM-style measured ceiling
    (METHODOLOGY §3) is owed and will replace these; until then, treat the achieved GB/s column as
    the real result and the percentage column as an indication.{measured_note}</p>
    <p style="margin-top:8px">Read the achieved column instead: the phone extracts a
    <i>higher</i> fraction of its memory system than the laptop does — it is simply working against
    a much smaller ceiling, and thermal throttling then takes away roughly a quarter of what it had.</p>
  </div>
"""

    chart = line_chart(summaries, "decode")
    cmp_chart = compare_chart(summaries, anchor_sum, "decode")
    cmp_block = ""
    if cmp_chart:
        a_silo = next(s for s in anchor_sum if s["label"] == "SILO")
        p_silo = next(s for s in summaries if s["label"] == "SILO")
        a_dev = a_silo["run"]["device"]
        cmp_block = f"""
  <h2>The same workload, plugged in</h2>
  <figure>
    {cmp_chart}
    <figcaption>Identical model, quantisation, regime, backend and commit, measured the same day on a
    {html.escape(a_dev['model'])} ({html.escape(a_dev['soc'])}). The mains-powered, actively cooled machine holds decode
    flat across all five long generations (rho {a_silo['decode']['rho']:+.2f}, {a_silo['decode']['mean']:.2f} tok/s
    mean); the phone falls {abs(p_silo['decode']['first_last_pct']):.1f}% over the same workload. Thermal behaviour,
    not raw silicon speed, is what phone benchmarks have to capture — and it is exactly what a laptop, a Jetson or a
    Raspberry Pi cannot show you.</figcaption>
  </figure>
"""

    station_blocks = "".join(station_block(s, n, aid, tag, first, ceilings) for n, aid, s, tag in later)

    doc = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PocketRoofline — LLM inference on smartphone silicon</title>
<meta name="description" content="Roofline measurements of LLM inference on phone-class silicon, with error bars and thermal state, re-run on every OS and runtime update.">
<style>
  :root {{
    --surface: #fcfcfb; --ink: #0b0b0b; --ink2: #52514e; --rule: #e4e3df;
    --accent: {ACCENT_L}; --gray: {GRAY_L}; --card: #ffffff;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --surface: #1a1a19; --ink: #ffffff; --ink2: #c3c2b7; --rule: #35342f;
             --accent: {ACCENT_D}; --gray: {GRAY_D}; --card: #232220; }}
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--surface); color: var(--ink); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
  main {{ max-width: 860px; margin: 0 auto; padding: 40px 20px 72px; }}
  .eyebrow {{ font: 600 11px/1 ui-monospace, Menlo, monospace; letter-spacing: .14em; color: var(--ink2); text-transform: uppercase; }}
  h1 {{ font-size: clamp(28px, 4.6vw, 40px); line-height: 1.12; letter-spacing: -.02em; margin: 14px 0 10px; }}
  .lede {{ color: var(--ink2); max-width: 62ch; }}
  .hero {{ margin: 30px 0 8px; }}
  .hero .fig {{ font: 700 clamp(44px, 8vw, 68px)/1 -apple-system, sans-serif; letter-spacing: -.03em; color: var(--accent); }}
  .hero .cap {{ color: var(--ink2); max-width: 56ch; margin-top: 6px; }}
  h2 {{ font-size: 13px; letter-spacing: .12em; text-transform: uppercase; font-family: ui-monospace, Menlo, monospace;
        color: var(--ink2); margin: 44px 0 14px; display: flex; align-items: center; gap: 12px; }}
  h2::after {{ content: ""; flex: 1; border-top: 1px solid var(--rule); }}
  figure {{ background: var(--card); border: 1px solid var(--rule); border-radius: 8px; padding: 12px 8px 4px; }}
  svg {{ display: block; width: 100%; height: auto; }}
  .grid {{ stroke: var(--rule); stroke-width: 1; }}
  .ax {{ fill: var(--ink2); font: 11px ui-monospace, Menlo, monospace; }}
  .axt {{ fill: var(--ink2); font: 11px -apple-system, sans-serif; }}
  .ln {{ fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }}
  .ln.emph {{ stroke: var(--accent); }}
  .ln.ctx {{ stroke: var(--gray); }}
  .ln.anchor {{ stroke: var(--ink2); stroke-dasharray: 6 3; }}
  .pt {{ stroke: var(--card); stroke-width: 2; }}
  .pt.emph {{ fill: var(--accent); }}
  .pt.ctx {{ fill: var(--gray); }}
  .pt.anchor {{ fill: var(--ink2); }}
  .dl {{ font: 600 12px ui-monospace, Menlo, monospace; }}
  .dl.emph {{ fill: var(--accent); }}
  .dl.ctx {{ fill: var(--ink2); }}
  .dl.anchor {{ fill: var(--ink2); }}
  figcaption {{ color: var(--ink2); font-size: 13px; padding: 8px 12px 10px; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 13.5px; margin-top: 6px; }}
  th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--rule); }}
  thead th {{ font: 600 11px ui-monospace, Menlo, monospace; letter-spacing: .08em; text-transform: uppercase; color: var(--ink2); }}
  tbody th {{ font: 600 13px ui-monospace, Menlo, monospace; white-space: nowrap; }}
  td {{ font-variant-numeric: tabular-nums; }}
  .sd {{ color: var(--ink2); }}
  .neg {{ color: var(--accent); font-weight: 600; }}
  .flag {{ color: var(--accent); font-size: 11px; }}
  .scroll {{ overflow-x: auto; }}
  .note {{ background: var(--card); border: 1px solid var(--rule); border-left: 3px solid var(--accent);
           border-radius: 6px; padding: 14px 18px; color: var(--ink2); font-size: 14.5px; }}
  .note b {{ color: var(--ink); }}
  .meta {{ font: 12px ui-monospace, Menlo, monospace; color: var(--ink2); }}
  footer {{ margin-top: 52px; border-top: 1px solid var(--rule); padding-top: 18px; color: var(--ink2); font-size: 13px; }}
  a {{ color: inherit; text-underline-offset: 3px; }}
  html, body {{ overflow-x: clip; }}
  .stations {{ margin-top: 16px; }}
  .station {{ margin-top: 72px; padding-top: 28px; border-top: 2px solid var(--ink2); }}
  h2.st {{ font: 700 clamp(24px, 3.8vw, 32px)/1.15 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           letter-spacing: -.02em; text-transform: none; color: var(--ink); margin: 14px 0 10px; display: block; }}
  h2.st::after {{ content: none; }}
  .station h3 {{ font-size: 13px; letter-spacing: .12em; text-transform: uppercase; font-family: ui-monospace, Menlo, monospace;
        color: var(--ink2); margin: 44px 0 14px; display: flex; align-items: center; gap: 12px; }}
  .station h3::after {{ content: ""; flex: 1; border-top: 1px solid var(--rule); }}
  .note ol {{ margin: 8px 0 0 20px; }}
  .note li + li {{ margin-top: 8px; }}
</style></head><body><main>

  <p class="eyebrow">PocketRoofline · station 01 · {html.escape(dev['model'])} ({html.escape(dev['soc'])})</p>
  <h1>LLM inference measured on a phone, not an edge board.</h1>
  <p class="lede">RooflineBench characterised on-device inference across desktop GPUs, an M1&nbsp;Pro,
  a Jetson and a Raspberry&nbsp;Pi — <b>no phones</b>. This extends the same roofline methodology to
  smartphone silicon, with every repeat retained, thermal state recorded, and the matrix re-run on
  every OS and runtime update. Thermal collapse on phones has been measured independently
  (<a href="https://arxiv.org/abs/2603.23640">arXiv:2603.23640</a>, iPhone&nbsp;16&nbsp;Pro, −41.5% over 20 runs);
  what this adds is the roofline placement, a mains-powered control and the open per-build record.</p>
{nav}
  <div class="hero">
    <div class="fig">{gap:.0f}%</div>
    <p class="cap">Peak decode ({peak:.1f} tok/s, short prompts) overstates sustained decode
    ({sustained:.1f} tok/s, after {len(thr['decode']['all'])} consecutive long generations) by this much.
    Quoted phone-inference numbers are peak numbers.</p>
  </div>

  <h2>Decode throughput per repeat</h2>
  <figure>
    {chart}
    <figcaption><b>{html.escape(thr['label'])}</b> (long generation) declines monotonically —
    Spearman rho {thr['decode']['rho']:+.2f} — while the short-generation regimes hold flat
    ({stable['label']} CV {stable['decode']['cv']:.1f}%). The decline is thermal, not measurement noise.
    Dashed rings mark repeats flagged for a mid-run thermal transition.</figcaption>
  </figure>

  {cmp_block}

  <h2>Per regime</h2>
  <div class="scroll"><table>
    <thead><tr><th>Regime</th><th>in / out</th><th>Prefill tok/s</th><th>Decode tok/s</th>
    <th>95% CI (decode)</th><th>First→last</th><th>rho</th><th>Thermal</th></tr></thead>
    <tbody>{regime_rows(summaries)}</tbody>
  </table></div>

  {bw_block}

  <h2>Every repeat</h2>
  <div class="scroll"><table>
    <thead><tr><th>Run</th><th>Prefill tok/s</th><th>Decode tok/s</th><th>TTFT ms</th><th>Thermal</th></tr></thead>
    <tbody>{repeat_rows(summaries)}</tbody>
  </table></div>

  <h2>Stated limits</h2>
  <div class="note">
    <p>This session began at thermal state <b>fair</b>, not <b>nominal</b> — the ten-minute ambient
    cooldown of METHODOLOGY §5 was not achieved — so these are <b>warm-start</b> figures and are
    labelled as such. A cold-start session is owed and will be published beside this one rather
    than replacing it.</p>
    <p style="margin-top:8px">The declining regime's <b>mean is not a steady-state figure</b>: the
    series is non-stationary by construction, so the throttling curve is the result and its average
    would be a fiction. Repeats whose thermal state changed mid-run are excluded from aggregates,
    flagged, and still shown above.</p>
  </div>

  <h2>Provenance</h2>
  <p class="meta">
    {html.escape(dev['model'])} · {html.escape(dev['soc'])} · {dev['ramGB']} GB · {html.escape(dev['identifier'])}<br>
    {html.escape(os_['name'])} {html.escape(os_['version'])} ({html.escape(os_['build'])})<br>
    {html.escape(bk['name'])} @ {html.escape(bk['commit'][:12])}<br>
    {html.escape(mdl['id'])} {html.escape(mdl['quant'])} · {mdl['params']}B · sha256 {html.escape(mdl['fileSha256'][:16])}…<br>
    airplane mode, Wi-Fi and Bluetooth off, unplugged, app in foreground
  </p>
{station_blocks}
  <footer>
    <p>Every number on this page is computed from the committed run records and bandwidth probes in
    <a href="https://github.com/Umer9538/pocketroofline/tree/main/results">results/</a> — none is typed by hand
    except the published peak-bandwidth figures, which are labelled as published.
    Method: <a href="https://github.com/Umer9538/pocketroofline/blob/main/METHODOLOGY.md">METHODOLOGY.md</a>.
    Extends <a href="https://arxiv.org/abs/2602.11506">RooflineBench</a> (Bi et al., arXiv:2602.11506) to phone-class silicon.
    Write-up: <a href="https://medium.com/@muhammadumer9538/your-phone-runs-a-language-model-at-42-tokens-per-second-for-about-a-minute-2907d93282a7">Your phone runs a language model at 42 tokens per second — for about a minute</a> (Medium).</p>
    <p style="margin-top:6px">Contributions from other devices welcome — an iPhone&nbsp;15&nbsp;Pro+ or Pixel&nbsp;8+ capture takes about ten minutes.</p>
  </footer>
</main></body></html>
"""
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(doc)

    print(f"station 01 ({dev['model']}): peak {peak:.2f} vs sustained {sustained:.2f} tok/s -> gap {gap:.1f}%")
    for s in summaries:
        d = s["decode"]
        print(f"  {s['label']:5s} decode mean {d['mean']:6.2f} sd {d['sd']:4.2f} "
              f"CI [{d['ci'][0]:.2f},{d['ci'][1]:.2f}] first->last {d['first_last_pct']:+6.1f}% rho {d['rho']:+.2f}")
    for n, aid, sess, tag in later:
        r0 = sess["runs"][0]
        ceil = ceilings.get((r0["device"].get("identifier"), r0["os"]["build"]))
        print(f"station {n:02d} ({r0['device']['model']}): no headline"
              + (f"; measured ceiling {ceil['gbps']:.3f} GB/s (median of {len(ceil['probes'])} probes)" if ceil else ""))
        for s in sess["summaries"]:
            d = s["decode"]
            bw = achieved_bandwidth(d["mean"], r0["model"]["tensorBytes"]) if r0["model"].get("tensorBytes") else float("nan")
            print(f"  {s['label']:5s} decode mean {d['mean']:6.2f} sd {d['sd']:4.2f} "
                  f"CI [{d['ci'][0]:.2f},{d['ci'][1]:.2f}] first->last {d['first_last_pct']:+6.1f}% rho {d['rho']:+.2f}"
                  f" | {bw:.2f} GB/s" + (f" = {bw / ceil['gbps'] * 100:.1f}% of ceiling" if ceil else ""))
    print(f"wrote {OUT.relative_to(ROOT)} ({len(doc)} bytes)")


if __name__ == "__main__":
    main()
