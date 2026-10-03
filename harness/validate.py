#!/usr/bin/env python3
"""Validate run records against schema/run.schema.json.

Uses the `jsonschema` package when it is installed; otherwise falls back to a
small built-in validator covering the keywords the schema actually uses
(type, required, properties, additionalProperties, enum, const, items,
minItems, minimum, maximum, exclusiveMinimum, minLength, pattern).

Usage (from the repo root):
    python3 harness/validate.py                  # every results/*.json
    python3 harness/validate.py a.json b.json    # specific files

Exits non-zero if any record is invalid.
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schema" / "run.schema.json"

_TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool,
    "integer": int, "number": (int, float),
}


def load_schema():
    return json.loads(SCHEMA_PATH.read_text())


def _is_type(v, t):
    if t in ("integer", "number") and isinstance(v, bool):
        return False
    if t == "integer" and isinstance(v, float):
        return v.is_integer()
    return isinstance(v, _TYPES[t])


def _builtin(inst, sch, path, errs):
    p = path or "<root>"
    if "const" in sch and inst != sch["const"]:
        errs.append(f"{p}: expected {sch['const']!r}, got {inst!r}")
    if "enum" in sch and inst not in sch["enum"]:
        errs.append(f"{p}: {inst!r} not one of {sch['enum']}")
    t = sch.get("type")
    if t and not _is_type(inst, t):
        errs.append(f"{p}: expected {t}, got {type(inst).__name__}")
        return
    if isinstance(inst, (int, float)) and not isinstance(inst, bool):
        if "minimum" in sch and inst < sch["minimum"]:
            errs.append(f"{p}: {inst} < minimum {sch['minimum']}")
        if "maximum" in sch and inst > sch["maximum"]:
            errs.append(f"{p}: {inst} > maximum {sch['maximum']}")
        if "exclusiveMinimum" in sch and inst <= sch["exclusiveMinimum"]:
            errs.append(f"{p}: {inst} <= exclusiveMinimum {sch['exclusiveMinimum']}")
    if isinstance(inst, str):
        if "minLength" in sch and len(inst) < sch["minLength"]:
            errs.append(f"{p}: shorter than {sch['minLength']}")
        if "pattern" in sch and not re.search(sch["pattern"], inst):
            errs.append(f"{p}: {inst!r} does not match {sch['pattern']}")
    if isinstance(inst, dict):
        props = sch.get("properties", {})
        for k in sch.get("required", []):
            if k not in inst:
                errs.append(f"{p}: missing required '{k}'")
        for k, v in inst.items():
            sub = f"{path}.{k}" if path else k
            if k in props:
                _builtin(v, props[k], sub, errs)
            elif sch.get("additionalProperties") is False:
                errs.append(f"{p}: unexpected property '{k}'")
    if isinstance(inst, list):
        if "minItems" in sch and len(inst) < sch["minItems"]:
            errs.append(f"{p}: fewer than {sch['minItems']} items")
        if "items" in sch:
            for i, v in enumerate(inst):
                _builtin(v, sch["items"], f"{path}[{i}]", errs)


def validate(record, schema=None):
    """Return a list of human-readable error strings (empty = valid)."""
    schema = schema or load_schema()
    try:
        import jsonschema
    except ImportError:
        errs = []
        _builtin(record, schema, "", errs)
        return errs
    v = jsonschema.Draft202012Validator(schema)
    return [f"{'.'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}"
            for e in v.iter_errors(record)]


def engine():
    try:
        import jsonschema  # noqa: F401
        return "jsonschema"
    except ImportError:
        return "built-in"


def main(argv):
    files = [pathlib.Path(f) for f in argv] or sorted((ROOT / "results").glob("*.json"))
    schema = load_schema()
    bad = 0
    for f in files:
        errs = validate(json.loads(f.read_text()), schema)
        print(f"{'FAIL' if errs else 'ok  '}  {f}")
        for e in errs:
            print(f"      {e}")
        bad += bool(errs)
    print(f"{len(files) - bad}/{len(files)} valid ({engine()} validator)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
