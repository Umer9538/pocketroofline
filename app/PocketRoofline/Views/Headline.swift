import Foundation

/// The result's headline wording, derived only from measured values.
struct Headline {
    let peak: Double
    let sustained: Double
    let dropPercent: Double
    /// Hottest thermal state seen during the run.
    let hottest: ThermalLevel

    init?(capture: Capture) {
        guard let peak = capture.peakDecodeTokensPerSec,
              let sustained = capture.sustainedDecodeTokensPerSec,
              let drop = capture.dropPercent else { return nil }
        self.peak = peak
        self.sustained = sustained
        self.dropPercent = drop
        self.hottest = capture.hottestThermal ?? .nominal
    }

    /// "42.8 → 30.9 tok/s"
    var speeds: String {
        "\(Format.tokensPerSecond(peak)) → \(Format.tokensPerSecond(sustained)) tok/s"
    }

    /// "drops 28% when hot". Only says "hot" if iOS reported at least `serious`; `fair` is
    /// merely "slightly elevated" and doesn't justify the word.
    var dropSummary: String {
        let rounded = Int(dropPercent.rounded())
        guard rounded > 0 else {
            return rounded == 0 ? "holds its speed under sustained load" : "speeds up \(-rounded)% under sustained load"
        }
        return hottest >= .serious ? "drops \(rounded)% when hot" : "drops \(rounded)% under sustained load"
    }
}
