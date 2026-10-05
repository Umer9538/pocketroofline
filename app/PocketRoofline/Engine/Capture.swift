import Foundation

/// One complete session, in the shape the on-device harness emits (one object, all regimes).
/// `harness/finalize.py` splits it into per-regime records for `results/`.
/// Unlike the harness, the app measures every field itself, so there are no FILL-IN placeholders.
struct Capture: Codable, Sendable, Hashable {
    var schemaVersion = 1
    var source = "app"
    var appVersion: String
    var capturedAt: Date
    var matrixVersion: String
    var device: Device
    var os: OperatingSystem
    var backend: Backend
    var model: Model
    var conditions: Conditions
    var regimes: [RegimeResult]

    struct Device: Codable, Sendable, Hashable {
        var model: String
        var identifier: String
        var soc: String
        var ramGB: Int
    }

    struct OperatingSystem: Codable, Sendable, Hashable {
        var name: String
        var version: String
        var build: String
    }

    struct Backend: Codable, Sendable, Hashable {
        var name: String
        var version: String
        var commit: String
        var buildFlags: String
    }

    struct Model: Codable, Sendable, Hashable {
        var id: String
        var params: Double
        var quant: String
        var fileSha256: String
        var tensorBytes: Int
    }

    struct Conditions: Codable, Sendable, Hashable {
        /// Nil when iOS couldn't report the power state; omitted from the JSON rather than guessed.
        var charging: Bool?
        var airplaneMode: Bool
        var batteryStartPct: Double?
        var batteryEndPct: Double?
        var lowPowerMode: Bool
    }
}

struct RegimeResult: Codable, Sendable, Hashable, Identifiable {
    var label: RegimeLabel
    var promptTokens: Int
    var generateTokens: Int
    var repeats: [RepeatResult]

    var id: RegimeLabel { label }
}

struct RepeatResult: Codable, Sendable, Hashable, Identifiable {
    var index: Int
    var prefillTokensPerSec: Double
    var decodeTokensPerSec: Double
    var ttftMs: Double
    var peakResidentMB: Double?
    var thermalStateStart: ThermalLevel
    var thermalStateEnd: ThermalLevel

    var id: Int { index }
}

// MARK: - Headline figures

extension Capture {
    func regime(_ label: RegimeLabel) -> RegimeResult? {
        regimes.first { $0.label == label }
    }

    /// Mean decode tok/s over the SISO repeats: the device's speed before it heats up.
    var peakDecodeTokensPerSec: Double? {
        guard let repeats = regime(.siso)?.repeats, !repeats.isEmpty else { return nil }
        return repeats.map(\.decodeTokensPerSec).reduce(0, +) / Double(repeats.count)
    }

    /// Decode tok/s of the final SILO repeat. The SILO series falls as the device heats, so its
    /// mean describes no real moment and is deliberately never offered as a figure.
    var sustainedDecodeTokensPerSec: Double? {
        regime(.silo)?.repeats.last?.decodeTokensPerSec
    }

    /// (peak − sustained) / peak × 100: how much of its peak speed the device loses.
    var dropPercent: Double? {
        guard let peak = peakDecodeTokensPerSec, let sustained = sustainedDecodeTokensPerSec, peak > 0 else {
            return nil
        }
        return (peak - sustained) / peak * 100
    }

    var thermalAtStart: ThermalLevel? { regimes.first?.repeats.first?.thermalStateStart }
    var thermalAtEnd: ThermalLevel? { regimes.last?.repeats.last?.thermalStateEnd }
    var hottestThermal: ThermalLevel? {
        regimes.flatMap(\.repeats).flatMap { [$0.thermalStateStart, $0.thermalStateEnd] }.max()
    }
}

// MARK: - Persistence

extension Capture {
    var fileName: String { "pocketroofline-\(Int(capturedAt.timeIntervalSince1970)).json" }

    func prettyJSON() throws -> Data {
        try Self.encoder(formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).encode(self)
    }

    func compactJSON() throws -> Data {
        try Self.encoder(formatting: [.sortedKeys, .withoutEscapingSlashes]).encode(self)
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

    /// Shared with `DiagnosticCapture`, so both files encode dates and keys the same way.
    static func encoder(formatting: JSONEncoder.OutputFormatting) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
