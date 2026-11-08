import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// Drives one matrix v1 run and publishes its progress for the UI.
///
/// The run screen stays still while a repeat measures: everything it shows lives in `screen`,
/// which changes only at repeat boundaries (the pause between repeats, or before the warmup for
/// the first one). Decode windows are collected off the main actor and published in that pause.
/// Captures made before this redrew a live chart every 16 tokens, which competed with Metal decode
/// for the GPU; `Capture.uiDuringRepeats` records which way a capture was made.
@MainActor
@Observable
final class BenchmarkSession {
    enum Phase: Equatable {
        case idle
        case preparing
        case warmup
        /// `repeatNumber` is 1-based, for display.
        case running(RegimeLabel, repeatNumber: Int)
        case finished(Capture, savedTo: URL?)
        case failed(message: String)
        case interrupted(Interruption)

        var isActive: Bool {
            switch self {
            case .preparing, .warmup, .running: true
            case .idle, .finished, .failed, .interrupted: false
            }
        }
    }

    enum Interruption: Equatable {
        case leftForeground
        case stoppedByUser
    }

    /// Everything the run screen draws, as one value so a boundary update is a single redraw.
    struct Screen: Equatable {
        enum Stage: Equatable {
            /// Loading the model.
            case preparing
            /// The repeat that is measuring now, or comes next after the pause or the warmup.
            case repeatUp(RegimeLabel, repeatNumber: Int)
        }

        var stage: Stage = .preparing
        /// Every decode window of the finished repeats.
        var points: [LivePoint] = []
        /// Decode tok/s of the last finished repeat (the measured figure, not a window).
        var lastRepeatDecodeTokensPerSecond: Double?
        var completedRepeats = 0
        /// Sampled at the boundary, so a thermal change mid-repeat doesn't redraw the chip.
        var thermal: ThermalLevel = .nominal
    }

    private(set) var phase: Phase = .idle
    /// Changes only between repeats. See the type's note.
    private(set) var screen = Screen()
    private(set) var completedRegimes: [RegimeResult] = []

    /// The finished repeats' decode windows (for the result screen's curve).
    var livePoints: [LivePoint] { screen.points }

    private let modelStore: ModelStore
    private let conditions: DeviceConditions
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingInterruption: Interruption?
    @ObservationIgnored private var hasHandledLaunchArgument = false
    private static let log = Logger(subsystem: "com.umer9538.pocketroofline", category: "benchmark")

    init(modelStore: ModelStore, conditions: DeviceConditions) {
        self.modelStore = modelStore
        self.conditions = conditions
    }

    // MARK: - Control

    func start() {
        guard !phase.isActive, let model = modelStore.verifiedFile else { return }
        screen = Screen(thermal: .current)
        completedRegimes = []
        pendingInterruption = nil
        phase = .preparing

        runTask = Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let capture = try await run(modelURL: model.url, modelSHA256: model.sha256)
                let savedTo = try? capture.saveToDocuments()
                Self.log.notice("finished; saved to \(savedTo?.path ?? "nowhere", privacy: .public)")
                phase = .finished(capture, savedTo: savedTo)
            } catch {
                // Once interrupted, any error (including GPU work refused in the background)
                // is a symptom of the interruption rather than a benchmark failure.
                if let interruption = pendingInterruption {
                    phase = .interrupted(interruption)
                } else if error is CancellationError {
                    phase = .interrupted(.stoppedByUser)
                } else {
                    phase = .failed(message: error.localizedDescription)
                }
            }
            runTask = nil
        }
    }

    /// Starts a run if the app was launched with `-PocketRooflineAutoRun benchmark`. Call it once
    /// the model check has finished; it acts at most once per launch.
    func startIfRequestedAtLaunch() {
        guard !hasHandledLaunchArgument else { return }
        hasHandledLaunchArgument = true
        guard LaunchAutoRun.requested == LaunchAutoRun.benchmark else { return }
        guard modelStore.verifiedFile != nil else {
            phase = .failed(message: "Launched to run the benchmark, but the model isn't downloaded and verified, so nothing ran.")
            Self.log.error("auto-run: the model isn't verified; nothing ran")
            return
        }
        Self.log.notice("auto-run: starting the matrix v1 benchmark")
        start()
    }

    func stop() {
        interrupt(.stoppedByUser)
    }

    /// iOS forbids GPU work in the background, and a run that was paused would no longer measure
    /// sustained load anyway, so backgrounding ends the run and discards it. `.inactive` (Control
    /// Center, a notification banner) keeps the GPU, so it must not throw away a five-minute run.
    func scenePhaseChanged(to scenePhase: ScenePhase) {
        if scenePhase == .background {
            interrupt(.leftForeground)
        }
    }

    /// Returns to the start screen, dropping any finished result from memory (it stays on disk).
    func reset() {
        guard !phase.isActive else { return }
        phase = .idle
        screen = Screen()
        completedRegimes = []
    }

    private func interrupt(_ reason: Interruption) {
        guard phase.isActive, pendingInterruption == nil else { return }
        pendingInterruption = reason
        runTask?.cancel()
    }

    // MARK: - Run

    private func run(modelURL: URL, modelSHA256: String) async throws -> Capture {
        let device = DeviceProfile.current()
        var recorder = ConditionsRecorder(conditions: conditions)
        recorder.sample()

        let engine = try await LlamaEngine.load(modelAt: modelURL)
        try Task.checkCancellation()

        // The screen now names the first repeat, which follows the warmup with no pause between,
        // so nothing on screen changes when it starts measuring.
        if let first = BenchmarkProtocol.regimes.first {
            screen.stage = .repeatUp(first.label, repeatNumber: 1)
        }
        screen.thermal = .current
        phase = .warmup
        let warmup = BenchmarkProtocol.warmup
        _ = try await engine.benchOnce(prompt: warmup.promptTokens, generate: warmup.generateTokens) { _ in }

        let clockStart = ContinuousClock.now
        var completedRepeatCount = 0
        for (regimeIndex, regime) in BenchmarkProtocol.regimes.enumerated() {
            var repeats: [RepeatResult] = []
            for index in 0..<BenchmarkProtocol.repeatsPerRegime {
                if completedRepeatCount > 0 {
                    try await Task.sleep(for: BenchmarkProtocol.pauseBetweenRepeats)
                }
                phase = .running(regime.label, repeatNumber: index + 1)
                recorder.sample()

                // Filled inside the engine's progress callback (same call site and cost as before),
                // without touching the main actor; read once the repeat is over.
                let trace = RepeatTrace()
                let thermalStart = ThermalLevel.current
                let sample = try await engine.benchOnce(
                    prompt: regime.promptTokens,
                    generate: regime.generateTokens
                ) { tick in
                    trace.append(LivePoint(
                        regime: regime.label,
                        repeatIndex: index,
                        tokensDone: tick.tokensDone,
                        secondsSinceStart: (ContinuousClock.now - clockStart).secondsValue,
                        tokensPerSecond: tick.windowTokensPerSecond,
                        thermal: .current
                    ))
                }
                let thermalEnd = ThermalLevel.current

                repeats.append(RepeatResult(
                    index: index,
                    prefillTokensPerSec: sample.prefillTokensPerSecond,
                    decodeTokensPerSec: sample.decodeTokensPerSecond,
                    ttftMs: sample.ttftMs,
                    peakResidentMB: ProcessMemory.residentMegabytes(),
                    thermalStateStart: thermalStart,
                    thermalStateEnd: thermalEnd
                ))
                completedRepeatCount += 1
                Self.log.notice("\(regime.label.rawValue, privacy: .public) repeat \(index + 1): decode \(sample.decodeTokensPerSecond, format: .fixed(precision: 2)) tok/s")

                // The one screen update per repeat, at the start of the pause (or just before
                // the result screen after the last repeat).
                var next = screen
                next.points.append(contentsOf: trace.points)
                next.lastRepeatDecodeTokensPerSecond = sample.decodeTokensPerSecond
                next.completedRepeats = completedRepeatCount
                next.thermal = thermalEnd
                if index + 1 < BenchmarkProtocol.repeatsPerRegime {
                    next.stage = .repeatUp(regime.label, repeatNumber: index + 2)
                } else if regimeIndex + 1 < BenchmarkProtocol.regimes.count {
                    next.stage = .repeatUp(BenchmarkProtocol.regimes[regimeIndex + 1].label, repeatNumber: 1)
                }
                screen = next
            }
            completedRegimes.append(RegimeResult(
                label: regime.label,
                promptTokens: regime.promptTokens,
                generateTokens: regime.generateTokens,
                repeats: repeats
            ))
        }
        recorder.sample()

        return Capture(
            appVersion: Bundle.main.appVersion,
            capturedAt: .now,
            matrixVersion: BenchmarkProtocol.matrixVersion,
            device: Capture.Device(
                model: device.marketingName,
                identifier: device.identifier,
                soc: device.soc,
                ramGB: device.ramGB
            ),
            os: Capture.OperatingSystem(name: device.osName, version: device.osVersion, build: device.osBuild),
            backend: Capture.Backend(
                name: LlamaEngine.backendName,
                version: LlamaEngine.backendVersion,
                commit: LlamaEngine.pinnedCommit,
                buildFlags: LlamaEngine.buildFlags
            ),
            model: Capture.Model(
                id: modelStore.model.id,
                params: engine.parametersInBillions,
                quant: modelStore.model.quant,
                fileSha256: modelSHA256,
                tensorBytes: engine.tensorBytes
            ),
            conditions: recorder.result,
            regimes: completedRegimes,
            uiDuringRepeats: .still
        )
    }
}

/// One repeat's decode windows, appended from the engine's progress callback.
private final class RepeatTrace: Sendable {
    private let state = OSAllocatedUnfairLock<[LivePoint]>(initialState: [])

    func append(_ point: LivePoint) {
        state.withLock { $0.append(point) }
    }

    var points: [LivePoint] {
        state.withLock { $0 }
    }
}

extension Bundle {
    /// "1.0 (1)"
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
