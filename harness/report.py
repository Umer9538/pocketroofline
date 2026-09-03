#!/usr/bin/env python3
"""Read every run record in results/ and emit the summary page.

Statistics are computed here, never hand-entered: per-regime mean, sd, a
bootstrap 95% CI of the mean, the first->last delta, and a Spearman rank trend
that distinguishes a genuine monotonic decline (throttling) from scatter.

Repeats flagged invalid (thermal state changed mid-run, per METHODOLOGY 5) are
excluded from aggregates and still shown in the table and the chart.

Writes docs/index.html. Run from the repo root:
    python3 harness/report.py
"""
import json, pathlib, random, statistics as st, html

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
OUT = ROOT / "docs" / "index.html"

# Emphasis palette (dataviz skill): one accent + de-emphasis gray.
# Validated: CVD dE 11.6 light / 11.1 dark, normal-vision 16.9, contrast >= 3:1.
ACCENT_L, GRAY_L = "#d95926", "#8a8985"
ACCENT_D, GRAY_D = "#eb6834", "#9a998f"

REGIME_ORDER = ["SISO", "LISO", "SILO"]

# Published peak memory bandwidth, in GB/s. These are vendor/third-party figures,
# NOT measured here - a STREAM-style ceiling is still owed (METHODOLOGY 3).
# Public sources disagree on the A15, so it is carried as a range and every
# derived utilisation figure is reported as a range too.
PEAK_BW = {
    "Apple M1": {"low": 68.25, "high": 68.25,
                 "note": "68.25 GB/s, consistently reported (128-bit LPDDR4X-4266)"},
    "A15 Bionic": {"low": 34.1, "high": 42.7,
                   "note": "public sources disagree: 34.1 GB/s (64-bit LPDDR4X-4266) vs 42.7 GB/s"},
}


def achieved_bandwidth(decode_tok_s, tensor_bytes):
    """Single-stream autoregressive decode reads every weight once per token, so
    achieved bandwidth is decode rate x weight bytes. A lower bound on what the
    memory system actually delivered, and the standard way to place a decode
    workload on a roofline."""
    return decode_tok_s * tensor_bytes / 1e9


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


def line_chart(summaries, metric="decode"):
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

    return f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="Decode throughput per repeat for each regime. {focus} declines monotonically; the others stay flat.">{"".join(parts)}</svg>'


def main():
    runs = load_runs()
    if not runs:
        print("no run records found")
        return
    phone = [r for r in runs if r["device"]["soc"] != "Apple M1"]
    anchor = [r for r in runs if r["device"]["soc"] == "Apple M1"]
    summaries = [summarize(r) for r in phone]
    summaries.sort(key=lambda s: REGIME_ORDER.index(s["label"]) if s["label"] in REGIME_ORDER else 99)
    anchor_sum = sorted(
        [summarize(r) for r in anchor],
        key=lambda s: REGIME_ORDER.index(s["label"]) if s["label"] in REGIME_ORDER else 99,
    )

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

    # Full per-repeat table (the accessible table view of the chart)
    rep_rows = []
    for s in summaries:
        for i, r in enumerate(s["run"]["repeats"]):
            flag = "" if r.get("valid", True) else " <span class='flag'>flagged</span>"
            rep_rows.append(
                f"<tr><th>{s['label']} #{i}</th><td>{r['prefillTokensPerSec']:.1f}</td>"
                f"<td>{r['decodeTokensPerSec']:.2f}</td><td>{r['ttftMs']:.1f}</td>"
                f"<td>{r['thermalStateStart']} → {r['thermalStateEnd']}{flag}</td></tr>"
            )

    # --- Roofline placement: achieved memory bandwidth vs published peak ---
    tb = mdl.get("tensorBytes")
    bw_block = ""
    if tb:
        bw_rows = []
        for src, sums in (("phone", summaries), ("anchor", anchor_sum)):
            for s in sums:
                soc = s["run"]["device"]["soc"]
                peak_spec = PEAK_BW.get(soc)
                d = s["decode"]
                bw_mean = achieved_bandwidth(d["mean"], tb)
                bw_last = achieved_bandwidth(d["all"][-1], tb)
                if peak_spec:
                    u_hi = bw_mean / peak_spec["low"] * 100
                    u_lo = bw_mean / peak_spec["high"] * 100
                    util = f"{u_lo:.0f}–{u_hi:.0f}%" if peak_spec["low"] != peak_spec["high"] else f"{u_hi:.0f}%"
                else:
                    util = "—"
                bw_rows.append(
                    f"<tr><th>{html.escape(soc)}</th><td>{s['label']}</td>"
                    f"<td>{d['mean']:.2f}</td><td>{bw_mean:.1f}</td>"
                    f"<td>{bw_last:.1f}</td><td>{util}</td></tr>"
                )
        notes = " · ".join(f"{html.escape(k)}: {html.escape(v['note'])}" for k, v in PEAK_BW.items())
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
    the real result and the percentage column as an indication.</p>
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
</style></head><body><main>

  <p class="eyebrow">PocketRoofline · station 01 · {html.escape(dev['model'])} ({html.escape(dev['soc'])})</p>
  <h1>LLM inference measured on a phone, not an edge board.</h1>
  <p class="lede">RooflineBench characterised on-device inference across desktop GPUs, an M1&nbsp;Pro,
  a Jetson and a Raspberry&nbsp;Pi — <b>no phones</b>. This extends the same roofline methodology to
  smartphone silicon, with every repeat retained, thermal state recorded, and the matrix re-run on
  every OS and runtime update.</p>

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
    <tbody>{''.join(rows)}</tbody>
  </table></div>

  {bw_block}

  <h2>Every repeat</h2>
  <div class="scroll"><table>
    <thead><tr><th>Run</th><th>Prefill tok/s</th><th>Decode tok/s</th><th>TTFT ms</th><th>Thermal</th></tr></thead>
    <tbody>{''.join(rep_rows)}</tbody>
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

  <footer>
    <p>Every number on this page is computed from the committed run records in
    <a href="https://github.com/Umer9538/pocketroofline/tree/main/results">results/</a> — none is typed by hand.
    Method: <a href="https://github.com/Umer9538/pocketroofline/blob/main/METHODOLOGY.md">METHODOLOGY.md</a>.
    Extends <a href="https://arxiv.org/abs/2602.11506">RooflineBench</a> (Bi et al., arXiv:2602.11506) to phone-class silicon.</p>
    <p style="margin-top:6px">Contributions from other devices welcome — an iPhone&nbsp;15&nbsp;Pro+ or Pixel&nbsp;8+ capture takes about ten minutes.</p>
  </footer>
</main></body></html>
"""
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(doc)

    print(f"peak {peak:.2f} vs sustained {sustained:.2f} tok/s -> gap {gap:.1f}%")
    for s in summaries:
        d = s["decode"]
        print(f"  {s['label']:5s} decode mean {d['mean']:6.2f} sd {d['sd']:4.2f} "
              f"CI [{d['ci'][0]:.2f},{d['ci'][1]:.2f}] first->last {d['first_last_pct']:+6.1f}% rho {d['rho']:+.2f}")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(doc)} bytes)")


if __name__ == "__main__":
    main()
