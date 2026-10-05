Raw run records land here, one JSON file per session, conforming to
../schema/run.schema.json. Files are never edited after commit: a correction is
a new run with a note, so the record stays auditable.

## Layout

- `*.json` in this directory: the run records, one per regime of a session, written by
  `harness/finalize.py` and checked by `harness/validate.py`. They are what `harness/report.py` reads.
- [`captures/`](captures/): the raw capture each session's records were finalized from, byte-for-byte as
  exported from the device, so the records can be regenerated and audited. The iPhone 15 Plus records came
  from `python3 harness/finalize.py "results/captures/pocketroofline-iPhone15,5-1791162656.json" --notes …`,
  with the notes text as it appears in each record. Captures are kept from 2026-10-05 on; earlier sessions'
  captures were not committed.
- [`bandwidth/`](bandwidth/): raw [Headroom](https://github.com/Umer9538/headroom) probe reports, byte-for-byte.
  Each runs Metal STREAM copy, scale, add and triad kernels over 128 MiB buffers. Together they give the
  measured bandwidth ceiling of METHODOLOGY §3: for each phone model and OS build, `harness/report.py` takes
  the median of the probes' verified GPU triad medians. Only probes taken under the session's conditions go
  here. Today that is four probes of the iPhone 15 Plus, taken 2026-10-05 01:05Z just before its run, at
  thermal state `fair` on battery. Three earlier pilot probes of that phone, taken while it was charging at
  thermal state `serious`, stay in the Headroom repository (`Calibration/runs/pilot/`) and are not used.

## Errata

- **2026-10-04 — `model.config.attention` in the six matrix-v1 records says `MHA`.** The GGUF header of
  `tinyllama-1.1b-1t-openorca.Q4_0.gguf` (SHA-256 `bd07d1c5…`) reports 32 attention heads and 4 KV heads, so the
  model is GQA. The field is descriptive only: no figure on the page or in the posts is computed from it. Per the
  policy above the records are left as committed; this note is the correction.
