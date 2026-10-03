import Foundation

/// One point on the live decode-speed curve: the speed over the last `LlamaEngine.tickInterval` tokens.
struct LivePoint: Identifiable, Sendable, Hashable {
    let regime: RegimeLabel
    let repeatIndex: Int
    let tokensDone: Int
    let secondsSinceStart: Double
    let tokensPerSecond: Double
    let thermal: ThermalLevel

    var id: String { "\(seriesID)-\(tokensDone)" }

    /// Each repeat is its own line segment, so the chart never draws across the gaps between them.
    var seriesID: String { "\(regime.rawValue)-\(repeatIndex)" }
}

extension Duration {
    var secondsValue: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
