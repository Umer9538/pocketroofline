import Foundation

/// One diagnostic session (`DiagnosticProtocol`). It has the same provenance fields as a
/// benchmark `Capture`, its own `kind` and `matrixVersion`, its own file name, and a per-window
/// decode trace for every repeat. It is never split into matrix v1 run records:
/// `harness/finalize.py` refuses it, and `harness/diagnose.py` reads it.
struct DiagnosticCapture: Codable, Sendable, Hashable {
    var kind = DiagnosticProtocol.kind
    var matrixVersion = DiagnosticProtocol.matrixVersion
    var source = "app"
    var appVersion: String
    var capturedAt: Date
    var device: Capture.Device
    var os: Capture.OperatingSystem
    var backend: Capture.Backend
    var model: Capture.Model
    var conditions: Capture.Conditions
    var plan = Plan()
    /// In run order: SILO first, then SISO.
    var regimes: [DiagnosticRegimeResult]

    /// What was run, written into the file so it reads without the app's source.
    struct Plan: Codable, Sendable, Hashable {
        var warmup = Warmup(
            promptTokens: DiagnosticProtocol.warmup.promptTokens,
            generateTokens: DiagnosticProtocol.warmup.generateTokens
        )
        var sequence = DiagnosticProtocol.sequence.map {
            Block(
                label: $0.regime.label,
                promptTokens: $0.regime.promptTokens,
                generateTokens: $0.regime.generateTokens,
                repeats: $0.repeats
            )
        }
        var pauseSeconds = DiagnosticProtocol.pauseBetweenRepeats.secondsValue
        var windowTokens = DiagnosticProtocol.windowTokens
        /// Nothing on screen changes while a repeat runs.
        var screen = "quiet"

        struct Warmup: Codable, Sendable, Hashable {
            var promptTokens: Int
            var generateTokens: Int
        }

        struct Block: Codable, Sendable, Hashable {
            var label: RegimeLabel
            var promptTokens: Int
            var generateTokens: Int
            var repeats: Int
        }
    }
}

struct DiagnosticRegimeResult: Codable, Sendable, Hashable, Identifiable {
    var label: RegimeLabel
    var promptTokens: Int
    var generateTokens: Int
    var repeats: [DiagnosticRepeat]

    var id: RegimeLabel { label }
}

/// A `RepeatResult` plus where it sits in time and its window trace.
struct DiagnosticRepeat: Codable, Sendable, Hashable, Identifiable {
    var index: Int
    /// Seconds since the first measured repeat began, taken as this repeat began.
    var startSeconds: Double
    var prefillTokensPerSec: Double
    var decodeTokensPerSec: Double
    var ttftMs: Double
    var peakResidentMB: Double?
    var thermalStateStart: ThermalLevel
    var thermalStateEnd: ThermalLevel
    /// Every consecutive `plan.windowTokens`-token window of the decode, in order.
    var windows: [DiagnosticWindow]

    var id: Int { index }

    /// (last window − first window) / first window × 100. Nil with fewer than two windows.
    var windowChangePercent: Double? {
        guard windows.count >= 2, let first = windows.first?.tokensPerSec, let last = windows.last?.tokensPerSec,
              first > 0 else { return nil }
        return (last - first) / first * 100
    }
}

/// The decode rate over one window of generated tokens.
struct DiagnosticWindow: Codable, Sendable, Hashable {
    /// Tokens generated at the end of the window: 64, 128, and so on.
    var tokensDone: Int
    var tokensPerSec: Double
    /// Seconds since the first measured repeat began, taken at the end of the window.
    var secondsSinceStart: Double
    /// `ProcessInfo.thermalState` at the end of the window.
    var thermalState: ThermalLevel
}

extension DiagnosticCapture {
    var thermalAtStart: ThermalLevel? { regimes.first?.repeats.first?.thermalStateStart }
    var thermalAtEnd: ThermalLevel? { regimes.last?.repeats.last?.thermalStateEnd }

    /// The `pocketroofline-diagnostic-` prefix keeps it apart from benchmark captures in Files.
    var fileName: String { "pocketroofline-diagnostic-\(Int(capturedAt.timeIntervalSince1970)).json" }

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
