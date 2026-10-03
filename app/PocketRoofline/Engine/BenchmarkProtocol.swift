import Foundation

/// RooflineBench's regime naming: short/long input, short/long output.
enum RegimeLabel: String, Codable, Sendable, CaseIterable, Hashable {
    case siso = "SISO"
    case liso = "LISO"
    case silo = "SILO"

    var summary: String {
        switch self {
        case .siso: "Short in, short out"
        case .liso: "Long in, short out"
        case .silo: "Short in, long out"
        }
    }
}

struct Regime: Sendable, Hashable {
    let label: RegimeLabel
    let promptTokens: Int
    let generateTokens: Int
}

/// Matrix v1, frozen. Every published capture used exactly these numbers, so changing
/// anything here breaks comparability with existing results; a change means matrix v2.
enum BenchmarkProtocol {
    static let matrixVersion = "v1"

    static let regimes: [Regime] = [
        Regime(label: .siso, promptTokens: 128, generateTokens: 128),
        Regime(label: .liso, promptTokens: 2048, generateTokens: 128),
        Regime(label: .silo, promptTokens: 128, generateTokens: 1024),
    ]

    static let repeatsPerRegime = 5

    /// Unrecorded, so shader compilation and first-touch page faults stay out of the data.
    static let warmup = Regime(label: .siso, promptTokens: 32, generateTokens: 16)

    static let pauseBetweenRepeats: Duration = .seconds(3)

    static var totalRepeats: Int { regimes.count * repeatsPerRegime }
}
