#!/usr/bin/env python3
"""Finalize an on-device PocketRoofline capture into schema-conforming run records.

Two kinds of capture are accepted:

* App captures (`"source": "app"`), from the public PocketRoofline iOS app. The
  app measures and fills every field itself, so no flags are needed:

      python3 harness/finalize.py pocketroofline-1790000000.json

* Harness captures, from the patched llama.swiftui harness. These carry
  `FILL-IN` placeholders for what the harness couldn't read (SoC, RAM, OS build,
  backend commit/version, weights SHA-256), which you supply as flags:

      python3 harness/finalize.py capture.json \\
          --soc "A15 Bionic" --ram 4 --os-build 23G93 \\
          --backend-commit 95ef7fc16054e63b427a3ef00188e055ef7586d8 \\
          --model-sha <sha256> --backend-version b6666 [--charging false]

Any flag given overrides the capture's value. If a required value is still
missing or `FILL-IN` after merging, the script stops and names the flag to pass.

The capture is split into one run record PER regime, each validated against
schema/run.schema.json before anything is written. A capture that records
charging, a network connection, or Low Power Mode is written with
`"valid": false` and the reason (METHODOLOGY.md §7). Simulator captures are
refused.

  --check         validate and print what would be written; write nothing
  --outdir DIR    write somewhere other than results/ (e.g. for tests)

No third-party deps (uses `jsonschema` for validation if installed).
"""
import argparse, copy, hashlib, json, pathlib, re, sys

sys.dont_write_bytecode = True  # keep harness/ free of __pycache__
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from validate import validate  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent


def slug(s): return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def missing(v):
    """True for absent values and harness placeholders ("FILL-IN", "FILL-IN-sw_vers", ramGB 0)."""
    if v is None:
        return True
    if isinstance(v, str):
        return not v.strip() or v.strip().upper().startswith("FILL-IN")
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v <= 0
    return False


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_bool(s, flag):
    if s.lower() in ("true", "yes", "1"):
        return True
    if s.lower() in ("false", "no", "0"):
        return False
    die(f"{flag} must be true or false, got {s!r}")


def session_invalid_reason(conditions):
    """METHODOLOGY.md §7 conditions that a capture records itself; None if none apply."""
    reasons = []
    if conditions.get("charging") is True:
        reasons.append("device was charging")
    if conditions.get("airplaneMode") is False:
        reasons.append("device was not offline (airplane mode)")
    if conditions.get("lowPowerMode") is True:
        reasons.append("Low Power Mode was on")
    return "; ".join(reasons) or None


def build_records(cap, a):
    if cap.get("partial"):
        die("this is a partial capture (the run did not finish); only complete captures can be finalized")
    for key in ("device", "os", "backend", "model", "regimes", "capturedAt"):
        if key not in cap:
            die(f"capture has no '{key}' — is this a PocketRoofline capture?")
    if "(Simulator)" in cap["device"].get("model", ""):
        die("this capture came from the iOS Simulator (CPU on a Mac), not a phone; it can't be added to results/")
    from_app = cap.get("source") == "app"

    dev = copy.deepcopy(cap["device"]); osv = copy.deepcopy(cap["os"])
    bk = copy.deepcopy(cap["backend"]); mdl = copy.deepcopy(cap["model"])

    # Flags override; otherwise keep the capture's value.
    if a.soc is not None: dev["soc"] = a.soc
    if a.ram is not None: dev["ramGB"] = a.ram
    if a.os_build is not None: osv["build"] = a.os_build
    if a.backend_commit is not None: bk["commit"] = a.backend_commit
    if a.backend_version: bk["version"] = a.backend_version
    if a.model_sha:
        mdl["fileSha256"] = a.model_sha
    elif a.model_file:
        mdl["fileSha256"] = sha256_file(a.model_file)

    required = [
        ("--soc", dev.get("soc")),
        ("--ram", dev.get("ramGB")),
        ("--os-build", osv.get("build")),
        ("--backend-commit", bk.get("commit")),
        ("--backend-version", bk.get("version")),
        ("--model-sha (or --model-file)", mdl.get("fileSha256")),
    ]
    gaps = [flag for flag, v in required if missing(v)]
    if gaps:
        die("the capture is missing values that must be supplied: pass "
            + ", ".join(gaps))

    conditions = dict(cap.get("conditions", {}))
    if a.charging is not None:
        conditions["charging"] = parse_bool(a.charging, "--charging")
    elif not from_app:
        # The harness never recorded power state; its runs were made unplugged by protocol.
        # The app omits `charging` only when iOS couldn't tell, so that stays unrecorded.
        conditions.setdefault("charging", False)
    invalid_reason = session_invalid_reason(conditions)

    # Many phones share a model and OS build, so app records also carry the capture time.
    stamp = "-" + re.sub(r"[^0-9tz]", "", cap["capturedAt"].lower()) if from_app else ""

    records = []
    for regime in cap["regimes"]:
        label = regime["label"]
        run_id = f"{slug(dev['model'])}-{osv['name'].lower()}{osv['version']}-{osv['build']}-{slug(mdl['id'])}-{mdl['quant'].lower()}{stamp}-{label.lower()}"
        record = {
            "schemaVersion": 1,
            "runId": run_id,
            "capturedAt": cap["capturedAt"],
            "matrixVersion": cap.get("matrixVersion", "v1"),
        }
        if cap.get("source"): record["source"] = cap["source"]
        if cap.get("appVersion"): record["appVersion"] = cap["appVersion"]
        record.update({
            "device": dev,
            "os": osv,
            "backend": bk,
            "model": mdl,
            "regime": {"promptTokens": regime["promptTokens"], "generateTokens": regime["generateTokens"], "label": label},
            "conditions": conditions,
            "repeats": regime["repeats"],
            "valid": invalid_reason is None,
        })
        if invalid_reason:
            record["invalidReason"] = invalid_reason
        if a.notes:
            record["notes"] = a.notes
        records.append(record)
    return records


def main():
    ap = argparse.ArgumentParser(description="Finalize a PocketRoofline capture into results/ run records.")
    ap.add_argument("capture")
    ap.add_argument("--soc", help="SoC name, e.g. 'A15 Bionic' (default: from capture)")
    ap.add_argument("--ram", type=float, help="RAM in GB (default: from capture)")
    ap.add_argument("--os-build", help="OS build, e.g. 23G83 (default: from capture)")
    ap.add_argument("--backend-commit", help="llama.cpp commit SHA (default: from capture)")
    ap.add_argument("--backend-version", default="", help="backend version/tag (default: from capture)")
    ap.add_argument("--model-sha", default="", help="weights SHA-256 (default: from capture)")
    ap.add_argument("--model-file", help="path to GGUF; SHA-256 computed if --model-sha omitted")
    ap.add_argument("--charging", help="true/false (default: from capture, else false)")
    ap.add_argument("--notes", default="")
    ap.add_argument("--outdir", help="output directory (default: results/)")
    ap.add_argument("--check", action="store_true", help="validate only; write nothing")
    a = ap.parse_args()

    try:
        cap = json.loads(pathlib.Path(a.capture).read_text())
    except (OSError, json.JSONDecodeError) as e:
        die(f"cannot read capture {a.capture}: {e}")

    records = build_records(cap, a)

    failed = False
    for r in records:
        for e in validate(r):
            print(f"invalid {r['runId']}: {e}", file=sys.stderr)
            failed = True
    if failed:
        die("records do not conform to schema/run.schema.json; nothing written")

    outdir = pathlib.Path(a.outdir).resolve() if a.outdir else ROOT / "results"

    def show(p):
        try:
            return str(p.relative_to(ROOT))
        except ValueError:
            return str(p)

    if a.check:
        print(f"ok: {len(records)} record(s) valid; would write:")
        for r in records:
            p = outdir / f"{r['runId']}.json"
            print(" ", show(p), "(exists, would overwrite)" if p.exists() else "")
        return

    outdir.mkdir(parents=True, exist_ok=True)
    print("wrote:")
    for r in records:
        p = outdir / f"{r['runId']}.json"
        p.write_text(json.dumps(r, indent=2) + "\n")
        print(" ", show(p))


if __name__ == "__main__":
    main()
