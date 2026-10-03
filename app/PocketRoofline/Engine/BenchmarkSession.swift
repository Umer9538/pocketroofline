import Foundation
import Observation
import SwiftUI
import UIKit

/// Drives one matrix v1 run and publishes its progress for the UI.
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

    private(set) var phase: Phase = .idle
    private(set) var livePoints: [LivePoint] = []
    private(set) var completedRegimes: [RegimeResult] = []
    private(set) var completedRepeatCount = 0

    var latestTokensPerSecond: Double? { livePoints.last?.tokensPerSecond }

    private let modelStore: ModelStore
    private let conditions: DeviceConditions
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingInterruption: Interruption?

    init(modelStore: ModelStore, conditions: DeviceConditions) {
        self.modelStore = modelStore
        self.conditions = conditions
    }

    // MARK: - Control

    func start() {
        guard !phase.isActive, let model = modelStore.verifiedFile else { return }
        livePoints = []
        completedRegimes = []
        completedRepeatCount = 0
        pendingInterruption = nil
        phase = .preparing

        runTask = Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let capture = try await run(modelURL: model.url, modelSHA256: model.sha256)
                phase = .finished(capture, savedTo: try? capture.saveToDocuments())
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
        livePoints = []
        completedRegimes = []
        completedRepeatCount = 0
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

        phase = .warmup
        let warmup = BenchmarkProtocol.warmup
        _ = try await engine.benchOnce(prompt: warmup.promptTokens, generate: warmup.generateTokens) { _ in }

        let (points, pointSink) = AsyncStream<LivePoint>.makeStream()
        let pointConsumer = Task {
            for await point in points { livePoints.append(point) }
        }
        defer { pointSink.finish() }

        let clockStart = ContinuousClock.now
        for regime in BenchmarkProtocol.regimes {
            var repeats: [RepeatResult] = []
            for index in 0..<BenchmarkProtocol.repeatsPerRegime {
                if completedRepeatCount > 0 {
                    try await Task.sleep(for: BenchmarkProtocol.pauseBetweenRepeats)
                }
                phase = .running(regime.label, repeatNumber: index + 1)
                recorder.sample()

                let thermalStart = ThermalLevel.current
                let sample = try await engine.benchOnce(
                    prompt: regime.promptTokens,
                    generate: regime.generateTokens
                ) { tick in
                    pointSink.yield(LivePoint(
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
            }
            completedRegimes.append(RegimeResult(
                label: regime.label,
                promptTokens: regime.promptTokens,
                generateTokens: regime.generateTokens,
                repeats: repeats
            ))
        }
        recorder.sample()

        pointSink.finish()
        await pointConsumer.value

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
            regimes: completedRegimes
        )
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
