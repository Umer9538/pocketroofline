import Foundation

/// The recovery test, `recovery-ladder-1`. It is not matrix v1 and its captures never become
/// benchmark results.
///
/// It asks one question: once the phone is heat-soaked, how long does decode take to get back to
/// its cold speed? It heats the phone with SILO back to back, then climbs a ladder of rests, each
/// followed by one short probe. The rests are cumulative: the phone keeps cooling through every
/// rest and probe, so each probe also records how long it has been since the heat phase ended.
/// Each pass reuses matrix v1's own definitions: the same regimes, warmup, pause, engine and
/// timing. The screen stays still while anything is measured and through every rest.
enum RecoveryProtocol {
    static let matrixVersion = "recovery-ladder-1"
    static let kind = "recovery"

    static let warmup = BenchmarkProtocol.warmup

    /// The heat phase: SILO 128→1024, recorded, with the usual pause before each repeat.
    static let heat = matrixV1(.silo)
    static let heatRepeats = 3

    /// Taken before every heat repeat, the first included, so the screen can change while nothing
    /// is measured.
    static let pauseBetweenRepeats = BenchmarkProtocol.pauseBetweenRepeats

    /// The rest ladder, in order. Each rest is the idle time from the end of the previous measured
    /// repeat to the start of the next probe.
    static let restLadder: [Duration] = [.seconds(30), .seconds(60), .seconds(120), .seconds(300)]

    /// The probe after each rest: SISO 128→128.
    static let probe = matrixV1(.siso)

    /// The trace's window size, as in the diagnostic. It must be a multiple of
    /// `LlamaEngine.tickInterval`.
    static let windowTokens = DiagnosticProtocol.windowTokens

    /// How often the thermal state is read during a rest. Reading it draws nothing.
    static let restThermalPoll: Duration = .seconds(1)

    /// About 8.5 min of rests, plus a warmup, three SILO repeats and four probes. On an
    /// iPhone 15 Plus SILO decodes at 30–60 tok/s, so the heat phase takes 1–2 min.
    static let estimatedMinutes = "about 11"

    static var totalSteps: Int { heatRepeats + restLadder.count }

    // MARK: - Debug-only rest scaling

    /// `-PocketRooflineRecoveryScale 0.1` shortens every rest by that factor, for simulator and
    /// pipeline tests. Debug builds only; a Release build ignores it. The factor is written into
    /// the capture, and `harness/recovery.py` flags any capture with a factor other than 1.
    static let restScaleDefaultsKey = "PocketRooflineRecoveryScale"

    /// The factor this launch uses: 1 unless a Debug build was given a value in (0, 1).
    static var restScale: Double {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: restScaleDefaultsKey)
        return value > 0 && value < 1 ? value : 1
        #else
        return 1
        #endif
    }

    private static func matrixV1(_ label: RegimeLabel) -> Regime {
        guard let regime = BenchmarkProtocol.regimes.first(where: { $0.label == label }) else {
            preconditionFailure("matrix v1 has no \(label.rawValue) regime")
        }
        return regime
    }
}

/// `-PocketRooflineAutoRun <value>` (UserDefaults argument domain) names a run to start at launch.
/// Each session acts only on its own value.
enum LaunchAutoRun {
    static let defaultsKey = "PocketRooflineAutoRun"
    static let benchmark = "benchmark"
    static let diagnostic = "diagnostic"
    static let recovery = "recovery"
    static let allValues = [benchmark, diagnostic, recovery]

    static var requested: String? { UserDefaults.standard.string(forKey: defaultsKey) }
}
