import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// What the recovery test's quiet screen shows. It changes only at step boundaries: as a heat
/// repeat's pause begins, and as a rest begins. Never while a repeat runs or during a rest.
struct RecoveryStatus: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case loading
        case warmup
        /// The heat repeat that runs after the current pause. 1-based.
        case heating(repeatNumber: Int)
        /// A rest, followed by its probe. `rung` is 1-based. `probeStartsAt` is fixed when the rest
        /// begins and shown as a clock time, so the screen needs no countdown.
        case resting(rung: Int, restSeconds: Double, probeStartsAt: Date)
    }

    struct Last: Equatable, Sendable {
        let title: String
        let decodeTokensPerSec: Double
    }

    var stage: Stage
    var last: Last?
    /// Read when the status was set, not live.
    var thermal: ThermalLevel
    var completedSteps = 0
}

/// Drives one recovery test (`RecoveryProtocol`) and keeps the screen still.
///
/// Like `DiagnosticSession`, it publishes nothing while a repeat runs. It also publishes nothing
/// during a rest: the rest's status, set once as the rest begins, already names the probe that
/// follows and the clock time it starts, so the next change comes only after that probe ends.
/// During a rest the thermal state is polled once a second into a local array; that reaches
/// neither the main actor's observers nor the screen.
@MainActor
@Observable
final class RecoverySession {
    enum Phase: Equatable {
        case idle
        case running(RecoveryStatus)
        case finished(RecoveryCapture, savedTo: URL?)
        case failed(message: String)
        case interrupted(BenchmarkSession.Interruption)

        var isActive: Bool {
            if case .running = self { true } else { false }
        }
    }

    private(set) var phase: Phase = .idle

    private let modelStore: ModelStore
    private let conditions: DeviceConditions
    private let benchmark: BenchmarkSession
    private let diagnostic: DiagnosticSession
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingInterruption: BenchmarkSession.Interruption?
    @ObservationIgnored private var hasHandledLaunchArgument = false

    private static let log = Logger(subsystem: "com.umer9538.pocketroofline", category: "recovery")

    init(modelStore: ModelStore, conditions: DeviceConditions, benchmark: BenchmarkSession, diagnostic: DiagnosticSession) {
        self.modelStore = modelStore
        self.conditions = conditions
        self.benchmark = benchmark
        self.diagnostic = diagnostic
    }

    // MARK: - Control

    func start() {
        guard !phase.isActive, !benchmark.phase.isActive, !diagnostic.phase.isActive,
              let model = modelStore.verifiedFile else { return }
        benchmark.reset()   // clears stale banners; finished results stay on disk
        diagnostic.reset()
        pendingInterruption = nil
        phase = .running(RecoveryStatus(stage: .loading, thermal: .current))

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
                Self.log.error("recovery test ended without a result: \(String(describing: error), privacy: .public)")
            }
            runTask = nil
        }
    }

    /// Starts a run if the app was launched with `-PocketRooflineAutoRun recovery`. Call it once
    /// the model check has finished; it acts at most once per launch.
    func startIfRequestedAtLaunch() {
        guard !hasHandledLaunchArgument else { return }
        hasHandledLaunchArgument = true
        guard LaunchAutoRun.requested == LaunchAutoRun.recovery else { return }
        guard modelStore.verifiedFile != nil else {
            phase = .failed(message: "Launched to run the recovery test, but the model isn't downloaded and verified, so nothing ran.")
            Self.log.error("auto-run: the model isn't verified; nothing ran")
            return
        }
        let scale = RecoveryProtocol.restScale
        Self.log.notice("auto-run: starting the recovery test (rest scale \(scale, format: .fixed(precision: 3)))")
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

    private func run(modelURL: URL, modelSHA256: String) async throws -> RecoveryCapture {
        let device = DeviceProfile.current()
        let plan = RecoveryCapture.Plan(restScale: RecoveryProtocol.restScale)
        var recorder = ConditionsRecorder(conditions: conditions)
        recorder.sample()

        let engine = try await LlamaEngine.load(modelAt: modelURL)
        try Task.checkCancellation()

        phase = .running(RecoveryStatus(stage: .warmup, thermal: .current))
        let warmup = RecoveryProtocol.warmup
        _ = try await engine.benchOnce(prompt: warmup.promptTokens, generate: warmup.generateTokens) { _ in }

        var last: RecoveryStatus.Last?
        var completedSteps = 0
        var origin: ContinuousClock.Instant?

        // Heat phase: SILO back to back, with the usual pause before each repeat.
        var heat: [DiagnosticRepeat] = []
        var lastEnd = ContinuousClock.now
        for index in 0..<RecoveryProtocol.heatRepeats {
            // This repeat's only screen update, made as its pause begins.
            recorder.sample()
            phase = .running(RecoveryStatus(
                stage: .heating(repeatNumber: index + 1),
                last: last,
                thermal: .current,
                completedSteps: completedSteps
            ))
            try await Task.sleep(for: RecoveryProtocol.pauseBetweenRepeats)

            let start = ContinuousClock.now
            let runStart = origin ?? start
            origin = runStart
            let (result, end) = try await measure(RecoveryProtocol.heat, index: index, engine: engine, origin: runStart, start: start)
            heat.append(result)
            lastEnd = end
            completedSteps += 1
            last = RecoveryStatus.Last(title: "Heat \(index + 1) (SILO)", decodeTokensPerSec: result.decodeTokensPerSec)
            Self.log.notice("heat \(index + 1)/\(RecoveryProtocol.heatRepeats): decode \(result.decodeTokensPerSec, format: .fixed(precision: 2)) tok/s, thermal \(result.thermalStateStart.rawValue, privacy: .public) -> \(result.thermalStateEnd.rawValue, privacy: .public)")
        }
        guard let runStart = origin else { preconditionFailure("the heat phase has at least one repeat") }
        let heatEnd = lastEnd

        // The ladder: rest, then probe. The rest runs from the end of the previous repeat.
        var probes: [RecoveryProbe] = []
        for (index, restSeconds) in plan.restSecondsPlanned.enumerated() {
            let restStart = lastEnd
            let deadline = restStart + .seconds(restSeconds)
            let thermalAtRestStart = ThermalLevel.current
            recorder.sample()
            // The only screen update for this rest and the probe after it.
            phase = .running(RecoveryStatus(
                stage: .resting(
                    rung: index + 1,
                    restSeconds: restSeconds,
                    probeStartsAt: Date.now.addingTimeInterval((deadline - ContinuousClock.now).secondsValue)
                ),
                last: last,
                thermal: thermalAtRestStart,
                completedSteps: completedSteps
            ))
            Self.log.notice("rest \(index + 1)/\(plan.restSecondsPlanned.count): \(restSeconds, format: .fixed(precision: 1)) s, thermal \(thermalAtRestStart.rawValue, privacy: .public)")
            let changes = try await rest(until: deadline, from: thermalAtRestStart, origin: runStart)

            let probeStart = ContinuousClock.now
            let (result, end) = try await measure(RecoveryProtocol.probe, index: index, engine: engine, origin: runStart, start: probeStart)
            probes.append(RecoveryProbe(
                index: index,
                restSecondsPlanned: restSeconds,
                restSecondsActual: (probeStart - restStart).secondsValue,
                restStartSeconds: (restStart - runStart).secondsValue,
                secondsSinceHeatEnd: (probeStart - heatEnd).secondsValue,
                thermalAtRestStart: thermalAtRestStart,
                thermalAtRestEnd: result.thermalStateStart,
                thermalChangesDuringRest: changes,
                result: result
            ))
            lastEnd = end
            completedSteps += 1
            last = RecoveryStatus.Last(title: "Probe \(index + 1) (SISO)", decodeTokensPerSec: result.decodeTokensPerSec)
            Self.log.notice("probe \(index + 1)/\(plan.restSecondsPlanned.count): decode \(result.decodeTokensPerSec, format: .fixed(precision: 2)) tok/s, \((probeStart - heatEnd).secondsValue, format: .fixed(precision: 1)) s after heat, thermal \(result.thermalStateStart.rawValue, privacy: .public) -> \(result.thermalStateEnd.rawValue, privacy: .public)")
        }
        recorder.sample()

        return RecoveryCapture(
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
            plan: plan,
            heat: heat,
            probes: probes
        )
    }

    /// One measured repeat with its window trace, as in the diagnostic. Returns it and the instant
    /// it ended.
    private func measure(
        _ regime: Regime,
        index: Int,
        engine: LlamaEngine,
        origin: ContinuousClock.Instant,
        start: ContinuousClock.Instant
    ) async throws -> (DiagnosticRepeat, ContinuousClock.Instant) {
        let trace = WindowTrace(
            runStart: origin,
            windowTokens: RecoveryProtocol.windowTokens,
            generateTokens: regime.generateTokens
        )
        let thermalStart = ThermalLevel.current
        let sample = try await engine.benchOnce(prompt: regime.promptTokens, generate: regime.generateTokens) { tick in
            trace.record(tick)
        }
        let thermalEnd = ThermalLevel.current
        let end = ContinuousClock.now
        let result = DiagnosticRepeat(
            index: index,
            startSeconds: (start - origin).secondsValue,
            prefillTokensPerSec: sample.prefillTokensPerSecond,
            decodeTokensPerSec: sample.decodeTokensPerSecond,
            ttftMs: sample.ttftMs,
            peakResidentMB: ProcessMemory.residentMegabytes(),
            thermalStateStart: thermalStart,
            thermalStateEnd: thermalEnd,
            windows: trace.windows
        )
        return (result, end)
    }

    /// Sleeps until `deadline`, reading the thermal state every `restThermalPoll` and keeping each
    /// change. Nothing here touches observed state, so nothing redraws. Cancellation (stop, or
    /// leaving the foreground) ends it at once.
    private func rest(
        until deadline: ContinuousClock.Instant,
        from initial: ThermalLevel,
        origin: ContinuousClock.Instant
    ) async throws -> [ThermalReading] {
        var changes: [ThermalReading] = []
        var current = initial
        while ContinuousClock.now < deadline {
            let next = min(deadline, ContinuousClock.now + RecoveryProtocol.restThermalPoll)
            try await Task.sleep(until: next, clock: .continuous)
            let state = ThermalLevel.current
            if state != current {
                changes.append(ThermalReading(secondsSinceStart: (ContinuousClock.now - origin).secondsValue, state: state))
                current = state
            }
        }
        return changes
    }

    private func save(_ capture: RecoveryCapture) -> URL? {
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
