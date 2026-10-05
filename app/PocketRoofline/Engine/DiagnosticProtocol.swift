import Foundation

/// The diagnostic run, `diag-silo-first-1`. It is not matrix v1 and its captures never become
/// benchmark results.
///
/// It exists to explain one observation: on the iPhone 15 Plus, decode fell from 59 tok/s (last
/// LISO repeat) to 30 tok/s (first SILO repeat) within seconds. So it starts with SILO on a cool
/// phone, then repeats SISO as a short-context check, keeps the screen still while a repeat runs,
/// and records the decode rate of every 64-token window. Each pass reuses matrix v1's own
/// definitions: the same regimes, warmup, pause, engine and timing. Only the order, the repeat
/// counts and the screen differ.
enum DiagnosticProtocol {
    static let matrixVersion = "diag-silo-first-1"
    static let kind = "diagnostic"

    struct Block: Sendable, Hashable {
        let regime: Regime
        let repeats: Int
    }

    /// Run order: the long test first, then the short one.
    static let sequence: [Block] = [
        Block(regime: matrixV1(.silo), repeats: 5),
        Block(regime: matrixV1(.siso), repeats: 3),
    ]

    static let warmup = BenchmarkProtocol.warmup

    /// Taken before every repeat, the first included, so the screen can change while nothing is
    /// measured.
    static let pauseBetweenRepeats = BenchmarkProtocol.pauseBetweenRepeats

    /// The trace's window size. It must be a multiple of `LlamaEngine.tickInterval`, because a
    /// window is built from the engine's contiguous progress ticks.
    static let windowTokens = 64

    static var totalRepeats: Int { sequence.reduce(0) { $0 + $1.repeats } }

    private static func matrixV1(_ label: RegimeLabel) -> Regime {
        guard let regime = BenchmarkProtocol.regimes.first(where: { $0.label == label }) else {
            preconditionFailure("matrix v1 has no \(label.rawValue) regime")
        }
        return regime
    }
}
