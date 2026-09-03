#!/usr/bin/env python3
"""Finalize an on-device PocketRoofline capture.

The iOS app emits a capture with the numbers it can measure and `FILL-IN`
placeholders for what it can't (SoC, RAM, OS build, backend commit, weights
SHA-256). This script fills those in from CLI flags, restructures the capture
into one schema-conforming run record PER regime (matching schema/run.schema.json),
and writes them to results/.

Usage:
  python3 harness/finalize.py capture.json \
      --soc "A15 Bionic" --ram 4 --os-build 23G93 \
      --backend-commit 95ef7fc16054e63b427a3ef00188e055ef7586d8 \
      --model-sha <sha256> --backend-version b6666 [--charging false]

No third-party deps. Prints the files written.
"""
import argparse, json, sys, hashlib, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent

def slug(s): return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--soc", required=True)
    ap.add_argument("--ram", type=float, required=True)
    ap.add_argument("--os-build", required=True)
    ap.add_argument("--backend-commit", required=True)
    ap.add_argument("--backend-version", default="")
    ap.add_argument("--model-sha", default="")
    ap.add_argument("--model-file", help="path to GGUF; SHA-256 computed if --model-sha omitted")
    ap.add_argument("--charging", default="false")
    ap.add_argument("--notes", default="")
    a = ap.parse_args()

    cap = json.loads(pathlib.Path(a.capture).read_text())

    sha = a.model_sha
    if not sha and a.model_file:
        h = hashlib.sha256()
        with open(a.model_file, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        sha = h.hexdigest()
    if not sha:
        print("warning: no model SHA (pass --model-sha or --model-file)", file=sys.stderr)
        sha = "UNKNOWN"

    dev = cap["device"]; osv = cap["os"]; mdl = cap["model"]; bk = cap["backend"]
    dev["soc"] = a.soc; dev["ramGB"] = a.ram
    osv["build"] = a.os_build
    bk["commit"] = a.backend_commit
    if a.backend_version: bk["version"] = a.backend_version
    mdl["fileSha256"] = sha
    charging = a.charging.lower() == "true"

    written = []
    outdir = ROOT / "results"
    outdir.mkdir(exist_ok=True)
    for regime in cap["regimes"]:
        label = regime["label"]
        run_id = f"{slug(dev['model'])}-{osv['name'].lower()}{osv['version']}-{osv['build']}-{slug(mdl['id'])}-{mdl['quant'].lower()}-{label.lower()}"
        record = {
            "schemaVersion": 1,
            "runId": run_id,
            "capturedAt": cap["capturedAt"],
            "matrixVersion": cap.get("matrixVersion", "v1"),
            "device": dev,
            "os": osv,
            "backend": bk,
            "model": mdl,
            "regime": {"promptTokens": regime["promptTokens"], "generateTokens": regime["generateTokens"], "label": label},
            "conditions": {**cap.get("conditions", {}), "charging": charging},
            "repeats": regime["repeats"],
            "valid": True,
        }
        if a.notes:
            record["notes"] = a.notes
        out = outdir / f"{run_id}.json"
        out.write_text(json.dumps(record, indent=2) + "\n")
        written.append(str(out.relative_to(ROOT)))

    print("wrote:")
    for w in written:
        print(" ", w)

if __name__ == "__main__":
    main()
