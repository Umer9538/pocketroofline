import Foundation

/// One recovery test (`RecoveryProtocol`). It has the same provenance fields as a benchmark
/// `Capture`, its own `kind` and `matrixVersion`, its own file name, the heat-phase repeats with
/// their window traces, and one probe per rest. It is never split into matrix v1 run records:
/// `harness/finalize.py` refuses it, and `harness/recovery.py` reads it.
struct RecoveryCapture: Codable, Sendable, Hashable {
    var kind = RecoveryProtocol.kind
    var matrixVersion = RecoveryProtocol.matrixVersion
    var source = "app"
    var appVersion: String
    var capturedAt: Date
    var device: Capture.Device
    var os: Capture.OperatingSystem
    var backend: Capture.Backend
    var model: Capture.Model
    var conditions: Capture.Conditions
    var plan: Plan
    /// SILO repeats, in run order. `startSeconds` and window times count from the first one.
    var heat: [DiagnosticRepeat]
    /// One per rest, in ladder order.
    var probes: [RecoveryProbe]

    /// What was run, written into the file so it reads without the app's source.
    struct Plan: Codable, Sendable, Hashable {
        var warmup = DiagnosticCapture.Plan.Warmup(
            promptTokens: RecoveryProtocol.warmup.promptTokens,
            generateTokens: RecoveryProtocol.warmup.generateTokens
        )
        var heat = DiagnosticCapture.Plan.Block(
            label: RecoveryProtocol.heat.label,
            promptTokens: RecoveryProtocol.heat.promptTokens,
            generateTokens: RecoveryProtocol.heat.generateTokens,
            repeats: RecoveryProtocol.heatRepeats
        )
        var pauseSeconds = RecoveryProtocol.pauseBetweenRepeats.secondsValue
        /// The ladder as designed, before any scaling.
        var restSecondsNominal = RecoveryProtocol.restLadder.map(\.secondsValue)
        /// 1 for a real run. Anything else came from the debug-only `-PocketRooflineRecoveryScale`.
        var restScale: Double
        /// The rests this run aimed for: nominal × scale.
        var restSecondsPlanned: [Double]
        var probe = DiagnosticCapture.Plan.Block(
            label: RecoveryProtocol.probe.label,
            promptTokens: RecoveryProtocol.probe.promptTokens,
            generateTokens: RecoveryProtocol.probe.generateTokens,
            repeats: 1
        )
        /// Rests follow each other with only a probe between them, so cooling is cumulative.
        var restsCumulative = true
        var windowTokens = RecoveryProtocol.windowTokens
        var restThermalPollSeconds = RecoveryProtocol.restThermalPoll.secondsValue
        /// Nothing on screen changes while a repeat runs or during a rest.
        var screen = "quiet"

        init(restScale: Double) {
            self.restScale = restScale
            restSecondsPlanned = RecoveryProtocol.restLadder.map { $0.secondsValue * restScale }
        }
    }
}

/// One rung of the ladder: the rest, then the probe that follows it.
struct RecoveryProbe: Codable, Sendable, Hashable, Identifiable {
    var index: Int
    var restSecondsPlanned: Double
    /// Measured: from the end of the previous measured repeat to the start of this probe.
    var restSecondsActual: Double
    /// Seconds since the first heat repeat began, taken as the rest began.
    var restStartSeconds: Double
    /// Seconds from the end of the last heat repeat to the start of this probe.
    var secondsSinceHeatEnd: Double
    var thermalAtRestStart: ThermalLevel
    var thermalAtRestEnd: ThermalLevel
    /// Every change of thermal state seen during the rest, polled every
    /// `plan.restThermalPollSeconds`. Empty if it held.
    var thermalChangesDuringRest: [ThermalReading]
    /// The probe itself. Its `thermalStateStart` is read as the rest ends and its
    /// `thermalStateEnd` as the probe ends.
    var result: DiagnosticRepeat

    var id: Int { index }
    var thermalAtProbeEnd: ThermalLevel { result.thermalStateEnd }
}

struct ThermalReading: Codable, Sendable, Hashable {
    /// Seconds since the first heat repeat began.
    var secondsSinceStart: Double
    var state: ThermalLevel
}

extension RecoveryCapture {
    var thermalAtStart: ThermalLevel? { heat.first?.thermalStateStart }

    /// The cold reference the app shows: the first window of the first heat repeat, the coolest
    /// moment of the run. `harness/recovery.py` reports against the same one.
    var coldWindowRate: Double? { heat.first?.windows.first?.tokensPerSec }

    var isScaled: Bool { plan.restScale != 1 }

    /// The `pocketroofline-recovery-` prefix keeps it apart from other captures in Files.
    var fileName: String { "pocketroofline-recovery-\(Int(capturedAt.timeIntervalSince1970)).json" }

    func prettyJSON() throws -> Data {
        try Capture.encoder(formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).encode(self)
    }

    /// Writes to the app's Documents folder, which the Files app exposes.
    func saveToDocuments() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let url = documents.appending(path: fileName)
        try prettyJSON().write(to: url, options: .atomic)
        return url
    }
}
