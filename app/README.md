# PocketRoofline for iOS

Tap **Run** and watch your iPhone's LLM decode speed, live, as the phone heats up. When the run
finishes you get a shareable result card, and you can submit the capture to the public
[PocketRoofline benchmark](https://github.com/Umer9538/pocketroofline) with one tap.

Every number comes from the device the app runs on. Nothing is simulated or estimated.

## What a run does

It runs the same fixed protocol as the published results (matrix v1):

- **Model:** TinyLlama-1.1B-1T-OpenOrca Q4_0. Every device runs this one model, downloaded once
  (637 MB) and checked against a pinned SHA-256. If the hash doesn't match, the app deletes the
  file and won't run.
- **Backend:** llama.cpp `95ef7fc` with Metal and all layers offloaded.
- **Regimes:** one warmup that isn't recorded, then SISO 128→128, LISO 2048→128 and SILO 128→1024,
  5 repeats each, with about 3 s between repeats. Tokens are synthetic. Prefill and decode are
  timed separately, the same way as `harness/ios-patch` (llama-bench style).
- **Recorded per repeat:** prefill tok/s, decode tok/s, TTFT, resident memory, and the thermal
  state at the start and end.

### Headline figures

| Figure | Definition |
| --- | --- |
| Peak | Mean decode tok/s over the 5 SISO repeats |
| Sustained | Decode tok/s of the **last** SILO repeat |
| Drop | (peak − sustained) / peak × 100 |

The card says "drops X% when hot" only if iOS reported at least the `serious` thermal state
during the run; otherwise it says "under sustained load".

The app never shows the SILO mean as a throughput. The series falls as the device heats up, so
its mean doesn't describe any real moment in the run.

### Conditions are recorded, not assumed

- `charging` is true if the phone was on external power at any sample, false only if every
  sample reported it unplugged, and omitted if iOS couldn't say (as in the simulator).
- `airplaneMode` is true only if `NWPathMonitor` reported **no usable network path at every
  sample**. iOS has no airplane-mode API, so the app records that radios were effectively off,
  never that a setting was on.
- `lowPowerMode` is true if Low Power Mode was on at any sample. Battery % is recorded at the
  start and end of the run.
- The app records no cooldown time, because it can't observe one. The thermal state of every
  repeat is in the data instead.

Leaving the app mid-run stops the run and discards it. iOS doesn't allow GPU work in the
background, and a paused run would no longer measure sustained load.

## Building

Requirements: Xcode 26 or later (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and a llama.cpp checkout next to this repo with its xcframework built:

```
Packages/
├── llama.cpp/            # at 95ef7fc16054e63b427a3ef00188e055ef7586d8
│   └── build-apple/llama.xcframework
└── pocketroofline/
    └── app/              # you are here
```

```sh
# once, in llama.cpp
git checkout 95ef7fc16054e63b427a3ef00188e055ef7586d8
./build-xcframework.sh

# then here
cd app
xcodegen generate            # project.yml → PocketRoofline.xcodeproj (also committed)
open PocketRoofline.xcodeproj
```

Set your team under Signing & Capabilities, then run on a physical iPhone. The simulator builds
and runs, but it uses the CPU instead of Metal. Its captures are labelled `llama.cpp-cpu` and the
device is marked as a simulator, so they can't pass for phone data: the result card says so,
the Submit button is replaced by a note, and `harness/finalize.py` refuses them.

Command-line build check (no signing needed):

```sh
xcodebuild -project PocketRoofline.xcodeproj -scheme PocketRoofline \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Code tour

| Path | Role |
| --- | --- |
| `Engine/LlamaEngine.swift` | Actor on its own serial queue that wraps llama.cpp. `benchOnce` is the measured repeat. |
| `Engine/BenchmarkSession.swift` | `@MainActor @Observable` state machine for the run. Publishes live points and handles interruption. |
| `Engine/BenchmarkProtocol.swift` | The frozen matrix v1 constants |
| `Engine/Capture.swift` | Codable capture plus the peak/sustained/drop helpers |
| `Engine/ModelStore.swift` | Download with progress and resume, then streamed SHA-256 verification |
| `Engine/DeviceProfile.swift` | Hardware identifier → name and SoC, measured RAM, OS build |
| `Engine/DeviceConditions.swift` | Live thermal, power, battery and network state |
| `Engine/ConditionsRecorder.swift` | Combines samples into the conditions a capture claims |
| `Engine/Submission.swift` | Builds the pre-filled GitHub issue URL |
| `Views/` | Home (checklist), Run (live chart), Result, the share card |

## Where captures go

Each finished run is saved as `Documents/pocketroofline-<unix-time>.json`. You can find it in the
Files app under *On My iPhone › PocketRoofline*. It uses the same single-object, all-regimes
shape as the harness capture, with every field filled in on the device, plus `"source": "app"`
and `appVersion`. `harness/finalize.py` splits it into per-regime records for `results/`.

**Submit to benchmark** always copies the compact JSON to the clipboard. It then opens the
`device-capture` issue form, pre-filled with the capture if the URL fits (under 7,500
characters). If it doesn't fit, you paste the capture in yourself.

## Honest limitations

- On iPhones not in the lookup table (anything newer than the iPhone 17 family), the model shows
  as `Unknown iPhone (<identifier>)` and the SoC as `unknown`. The app doesn't guess.
- RAM is `ProcessInfo.physicalMemory` rounded up to a whole GB. iOS reports a little less than
  the installed memory, so rounding to nearest would undercount (an 8 GB iPhone reports ~7.5).
- The thermal state is iOS's coarse four-level signal. iOS doesn't give apps die temperatures.
- `peakResidentMB` keeps the harness's method (resident size sampled right after each repeat),
  so app and harness numbers stay comparable.
