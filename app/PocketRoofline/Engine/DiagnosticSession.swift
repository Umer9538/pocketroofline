import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// What the quiet screen shows. It changes only between repeats, never while one runs.
struct DiagnosticStatus: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case loading
        case warmup
        /// The repeat that runs after the current pause. `repeatNumber` is 1-based.
        case measuring(regime: Regime, repeatNumber: Int, repeatsInRegime: Int)
    }

    struct LastRepeat: Equatable, Sendable {
        let regime: RegimeLabel
        let repeatNumber: Int
        let decodeTokensPerSec: Double
        let prefillTokensPerSec: Double
    }

    var stage: Stage
    var last: LastRepeat?
    /// Read when the status was set, not live.
    var thermal: ThermalLevel
    var completedRepeats = 0
}

/// Drives one diagnostic run (`DiagnosticProtocol`) and keeps the screen still while it measures.
///
/// Unlike `BenchmarkSession`, it publishes nothing while a repeat runs. `phase` changes only as a
/// pause begins, three seconds before the next repeat, so any redraw is finished before measuring
/// resumes. The window trace is built inside the engine's progress callback, on the engine's
/// queue, and never reaches the main actor until the repeat is over.
@MainActor
@Observable
final class DiagnosticSession {
    enum Phase: Equatable {
        case idle
        case running(DiagnosticStatus)
        case finished(DiagnosticCapture, savedTo: URL?)
        case failed(message: String)
        case interrupted(BenchmarkSession.Interruption)

        var isActive: Bool {
            if case .running = self { true } else { false }
        }
    }

    /// Launching with `-PocketRooflineAutoRun diagnostic` (UserDefaults argument domain) starts a
    /// diagnostic run as soon as the model is verified, for the simulator and scripted runs.
    static let autoRunDefaultsKey = "PocketRooflineAutoRun"
    static let autoRunDiagnosticValue = "diagnostic"

    private(set) var phase: Phase = .idle

    private let modelStore: ModelStore
    private let conditions: DeviceConditions
    private let benchmark: BenchmarkSession
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingInterruption: BenchmarkSession.Interruption?
    @ObservationIgnored private var hasHandledLaunchArgument = false

    private static let log = Logger(subsystem: "com.umer9538.pocketroofline", category: "diagnostic")

    init(modelStore: ModelStore, conditions: DeviceConditions, benchmark: BenchmarkSession) {
        self.modelStore = modelStore
        self.conditions = conditions
        self.benchmark = benchmark
    }

    // MARK: - Control

    func start() {
        guard !phase.isActive, !benchmark.phase.isActive, let model = modelStore.verifiedFile else { return }
        benchmark.reset()  // clears a stale "run stopped" banner; a benchmark result stays on disk
        pendingInterruption = nil
        phase = .running(DiagnosticStatus(stage: .loading, thermal: .current))

        runTask = Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let capture = try await run(modelURL: model.url, modelSHA256: model.sha256)
                phase = .finished(capture, savedTo: save(capture))
            } catch {
                // As in BenchmarkSession: once interrupted, any error is a symptom of the interruption.
                if let interruption = pendingInterruption {
                    phase = .interrupted(interruption)
                } else if error is CancellationError {
                    phase = .interrupted(.stoppedByUser)
                } else {
                    phase = .failed(message: error.localizedDescription)
                }
                Self.log.error("diagnostic run ended without a result: \(String(describing: error), privacy: .public)")
            }
            runTask = nil
        }
    }

    /// Starts a run if the app was launched with `-PocketRooflineAutoRun diagnostic`. Call it once
    /// the model check has finished; it acts at most once per launch.
    func startIfRequestedAtLaunch() {
        guard !hasHandledLaunchArgument else { return }
        hasHandledLaunchArgument = true
        guard let request = UserDefaults.standard.string(forKey: Self.autoRunDefaultsKey) else { return }
        guard request == Self.autoRunDiagnosticValue else {
            Self.log.error("ignoring -\(Self.autoRunDefaultsKey, privacy: .public) \(request, privacy: .public): the only value is \(Self.autoRunDiagnosticValue, privacy: .public)")
            return
        }
        guard modelStore.verifiedFile != nil else {
            phase = .failed(message: "Launched to run the diagnostic, but the model isn't downloaded and verified, so nothing ran.")
            Self.log.error("auto-run: the model isn't verified; nothing ran")
            return
        }
        Self.log.notice("auto-run: starting the diagnostic run")
        start()
    }

    func stop() {
        interrupt(.stoppedByUser)
    }

    /// Same rule as the benchmark: leaving the foreground ends the run and discards it.
    func scenePhaseChanged(to scenePhase: ScenePhase) {
        if scenePhase == .background {
            interrupt(.leftForeground)
        }
    }

    /// Back to the start screen. A finished capture stays on disk.
    func reset() {
        guard !phase.isActive else { return }
        phase = .idle
    }

    private func interrupt(_ reason: BenchmarkSession.Interruption) {
        guard phase.isActive, pendingInterruption == nil else { return }
        pendingInterruption = reason
        runTask?.cancel()
    }

    // MARK: - Run

    private func run(modelURL: URL, modelSHA256: String) async throws -> DiagnosticCapture {
        let device = DeviceProfile.current()
        var recorder = ConditionsRecorder(conditions: conditions)
        recorder.sample()

        let engine = try await LlamaEngine.load(modelAt: modelURL)
        try Task.checkCancellation()

        phase = .running(DiagnosticStatus(stage: .warmup, thermal: .current))
        let warmup = DiagnosticProtocol.warmup
        _ = try await engine.benchOnce(prompt: warmup.promptTokens, generate: warmup.generateTokens) { _ in }

        var regimes: [DiagnosticRegimeResult] = []
        var last: DiagnosticStatus.LastRepeat?
        var runStart: ContinuousClock.Instant?
        var completedRepeats = 0
        for block in DiagnosticProtocol.sequence {
            let regime = block.regime
            var repeats: [DiagnosticRepeat] = []
            for index in 0..<block.repeats {
                // This repeat's only screen update, made as its pause begins so that it is drawn
                // long before measuring starts.
                recorder.sample()
                phase = .running(DiagnosticStatus(
                    stage: .measuring(regime: regime, repeatNumber: index + 1, repeatsInRegime: block.repeats),
                    last: last,
                    thermal: .current,
                    completedRepeats: completedRepeats
                ))
                try await Task.sleep(for: DiagnosticProtocol.pauseBetweenRepeats)

                let repeatStart = ContinuousClock.now
                let origin = runStart ?? repeatStart
                runStart = origin
                let trace = WindowTrace(
                    runStart: origin,
                    windowTokens: DiagnosticProtocol.windowTokens,
                    generateTokens: regime.generateTokens
                )
                let thermalStart = ThermalLevel.current
                let sample = try await engine.benchOnce(
                    prompt: regime.promptTokens,
                    generate: regime.generateTokens
                ) { tick in
                    trace.record(tick)
                }
                let thermalEnd = ThermalLevel.current

                repeats.append(DiagnosticRepeat(
                    index: index,
                    startSeconds: (repeatStart - origin).secondsValue,
                    prefillTokensPerSec: sample.prefillTokensPerSecond,
                    decodeTokensPerSec: sample.decodeTokensPerSecond,
                    ttftMs: sample.ttftMs,
                    peakResidentMB: ProcessMemory.residentMegabytes(),
                    thermalStateStart: thermalStart,
                    thermalStateEnd: thermalEnd,
                    windows: trace.windows
                ))
                completedRepeats += 1
                last = DiagnosticStatus.LastRepeat(
                    regime: regime.label,
                    repeatNumber: index + 1,
                    decodeTokensPerSec: sample.decodeTokensPerSecond,
                    prefillTokensPerSec: sample.prefillTokensPerSecond
                )
                Self.log.notice("\(regime.label.rawValue, privacy: .public) \(index + 1)/\(block.repeats): decode \(sample.decodeTokensPerSecond, format: .fixed(precision: 2)) tok/s, prefill \(sample.prefillTokensPerSecond, format: .fixed(precision: 1)) tok/s, thermal \(thermalStart.rawValue, privacy: .public) -> \(thermalEnd.rawValue, privacy: .public)")
            }
            regimes.append(DiagnosticRegimeResult(
                label: regime.label,
                promptTokens: regime.promptTokens,
                generateTokens: regime.generateTokens,
                repeats: repeats
            ))
        }
        recorder.sample()

        return DiagnosticCapture(
            appVersion: Bundle.main.appVersion,
            capturedAt: .now,
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
            regimes: regimes
        )
    }

    private func save(_ capture: DiagnosticCapture) -> URL? {
        do {
            let url = try capture.saveToDocuments()
            Self.log.notice("saved \(url.path(percentEncoded: false), privacy: .public)")
            return url
        } catch {
            Self.log.error("couldn't save the capture: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Builds one repeat's window trace inside the engine's progress callback.
///
/// It runs on the engine's queue, inside the timed decode loop, so it does as little as possible:
/// per tick, one uncontended lock and two additions; per window, also a clock read, a thermal-state
/// read and an append into reserved capacity. Nothing reaches the main actor or the screen.
private final class WindowTrace: Sendable {
    private struct State: Sendable {
        var windows: [DiagnosticWindow] = []
        var pendingSeconds = 0.0
        var pendingTokens = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let runStart: ContinuousClock.Instant
    private let windowTokens: Int

    init(runStart: ContinuousClock.Instant, windowTokens: Int, generateTokens: Int) {
        precondition(windowTokens.isMultiple(of: LlamaEngine.tickInterval), "a window must be whole ticks")
        var initial = State()
        initial.windows.reserveCapacity(generateTokens / windowTokens)
        state = OSAllocatedUnfairLock(initialState: initial)
        self.runStart = runStart
        self.windowTokens = windowTokens
    }

    /// The engine's ticks are contiguous (each starts where the last ended), so their durations
    /// add up exactly to the window's. A trailing part-window is dropped; matrix v1's generate
    /// lengths are whole windows.
    func record(_ tick: DecodeTick) {
        state.withLock { current in
            current.pendingSeconds += Double(LlamaEngine.tickInterval) / tick.windowTokensPerSecond
            current.pendingTokens += LlamaEngine.tickInterval
            guard current.pendingTokens == windowTokens else { return }
            current.windows.append(DiagnosticWindow(
                tokensDone: tick.tokensDone,
                tokensPerSec: Double(current.pendingTokens) / current.pendingSeconds,
                secondsSinceStart: (ContinuousClock.now - runStart).secondsValue,
                thermalState: .current
            ))
            current.pendingSeconds = 0
            current.pendingTokens = 0
        }
    }

    var windows: [DiagnosticWindow] {
        state.withLock { $0.windows }
    }
}
