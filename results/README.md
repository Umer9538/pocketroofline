Raw run records land here, one JSON file per session, conforming to
../schema/run.schema.json. Files are never edited after commit: a correction is
a new run with a note, so the record stays auditable.

## Errata

- **2026-10-04 — `model.config.attention` in the six matrix-v1 records says `MHA`.** The GGUF header of
  `tinyllama-1.1b-1t-openorca.Q4_0.gguf` (SHA-256 `bd07d1c5…`) reports 32 attention heads and 4 KV heads, so the
  model is GQA. The field is descriptive only: no figure on the page or in the posts is computed from it. Per the
  policy above the records are left as committed; this note is the correction.
