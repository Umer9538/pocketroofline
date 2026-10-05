import SwiftUI

/// The diagnostic's screen while it runs, kept still on purpose: no chart, no live number, no
/// spinner, no animation. It is drawn from `status` alone, which `DiagnosticSession` sets only as
/// a pause begins, so nothing on screen changes while a repeat is measured.
struct DiagnosticRunView: View {
    let status: DiagnosticStatus
    let onStop: () -> Void

    @State private var isConfirmingStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Each text block keeps its full wrapped height; otherwise the stack, sharing space
            // with the spacer, can offer less and the text truncates.
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostic run")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Long test first · quiet screen · not a benchmark result")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Measuring — the screen stays still on purpose")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("Drawing uses the same GPU as the model, so nothing here moves while a repeat runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            statusCard
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("Keep PocketRoofline open. Switching apps or locking the screen stops the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                isConfirmingStop = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .confirmationDialog("Stop the diagnostic run?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                Button("Stop and discard", role: .destructive, action: onStop)
            } message: {
                Text("A partial run isn't saved.")
            }
        }
        .padding(20)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Now", now)
            row("Done", "\(status.completedRepeats) of \(DiagnosticProtocol.totalRepeats) repeats")
            row("Last", last)
            row("Thermal", status.thermal.displayName, dot: status.thermal.color)
            Text("Updated only between repeats, during the \(pauseSeconds) s pause before each one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
        // Belt and braces: whatever transaction delivers a new status, it is never animated.
        .transaction { $0.animation = nil }
    }

    private func row(_ title: String, _ value: String, dot: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }

    private var now: String {
        switch status.stage {
        case .loading:
            return "Loading the model"
        case .warmup:
            return "Warming up (not recorded)"
        case .measuring(let regime, let repeatNumber, let repeatsInRegime):
            return "\(regime.label.rawValue) \(repeatNumber) of \(repeatsInRegime) · \(regime.promptTokens)→\(regime.generateTokens) tokens"
        }
    }

    private var last: String {
        guard let last = status.last else { return "No repeat finished yet" }
        let prefill = last.prefillTokensPerSec.formatted(.number.precision(.fractionLength(0)))
        return "\(last.regime.rawValue) \(last.repeatNumber) · decode \(Format.tokensPerSecond(last.decodeTokensPerSec)) tok/s · prefill \(prefill)"
    }

    private var pauseSeconds: String {
        DiagnosticProtocol.pauseBetweenRepeats.secondsValue.formatted(.number.precision(.fractionLength(0)))
    }
}

#if DEBUG
#Preview {
    DiagnosticRunView(
        status: DiagnosticStatus(
            stage: .measuring(
                regime: DiagnosticProtocol.sequence[0].regime,
                repeatNumber: 2,
                repeatsInRegime: DiagnosticProtocol.sequence[0].repeats
            ),
            last: .init(regime: .silo, repeatNumber: 1, decodeTokensPerSec: 40.526, prefillTokensPerSec: 426.294),
            thermal: .fair,
            completedRepeats: 1
        ),
        onStop: {}
    )
}
#endif
