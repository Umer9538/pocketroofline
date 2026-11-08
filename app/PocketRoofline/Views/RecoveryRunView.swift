import SwiftUI

/// The recovery test's screen while it runs, kept still on purpose: no chart, no live number, no
/// countdown, no spinner, no animation. It is drawn from `status` alone, which `RecoverySession`
/// sets only as a heat repeat's pause begins or as a rest begins.
///
/// A rest shows the clock time its probe starts instead of a countdown. A countdown would redraw
/// once a second for up to five minutes while the phone is meant to cool; the clock time is fixed
/// when the rest begins, so it tells the same thing with no redraw at all.
struct RecoveryRunView: View {
    let status: RecoveryStatus
    let onStop: () -> Void

    @State private var isConfirmingStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Each text block keeps its full wrapped height; otherwise the stack, sharing space
            // with the spacer, can offer less and the text truncates.
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery test")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Heat, then rest and probe · quiet screen · not a benchmark result")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(explanation)
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
            .confirmationDialog("Stop the recovery test?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                Button("Stop and discard", role: .destructive, action: onStop)
            } message: {
                Text("A partial run isn't saved.")
            }
        }
        .padding(20)
    }

    private var isResting: Bool {
        if case .resting = status.stage { true } else { false }
    }

    private var headline: String {
        isResting ? "Resting — the screen stays still on purpose" : "Measuring — the screen stays still on purpose"
    }

    private var explanation: String {
        isResting
            ? "The phone is cooling. Drawing would warm it, so nothing here moves until the probe after this rest has finished."
            : "Drawing uses the same GPU as the model, so nothing here moves while a repeat runs."
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Now", now)
            if case .resting(_, _, let probeStartsAt) = status.stage {
                row("Probe", "starts by itself at about \(probeStartsAt.formatted(date: .omitted, time: .standard))")
            }
            row("Done", "\(status.completedSteps) of \(RecoveryProtocol.totalSteps) steps")
            row("Last", last)
            row("Thermal", status.thermal.displayName, dot: status.thermal.color)
            Text("Updated only between steps: as each heat repeat's \(pauseSeconds) s pause begins, and as each rest begins.")
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
        let heat = RecoveryProtocol.heat
        let probe = RecoveryProtocol.probe
        switch status.stage {
        case .loading:
            return "Loading the model"
        case .warmup:
            return "Warming up (not recorded)"
        case .heating(let repeatNumber):
            return "Heat \(repeatNumber) of \(RecoveryProtocol.heatRepeats) · \(heat.label.rawValue) \(heat.promptTokens)→\(heat.generateTokens) tokens"
        case .resting(let rung, let restSeconds, _):
            let rest = restSeconds.formatted(.number.precision(.fractionLength(0...1)))
            return "Rest \(rung) of \(RecoveryProtocol.restLadder.count) · \(rest) s, then probe \(probe.label.rawValue) \(probe.promptTokens)→\(probe.generateTokens)"
        }
    }

    private var last: String {
        guard let last = status.last else { return "No step finished yet" }
        return "\(last.title) · decode \(Format.tokensPerSecond(last.decodeTokensPerSec)) tok/s"
    }

    private var pauseSeconds: String {
        RecoveryProtocol.pauseBetweenRepeats.secondsValue.formatted(.number.precision(.fractionLength(0)))
    }
}

#if DEBUG
#Preview("Resting") {
    RecoveryRunView(
        status: RecoveryStatus(
            stage: .resting(rung: 2, restSeconds: 60, probeStartsAt: .now.addingTimeInterval(60)),
            last: .init(title: "Probe 1 (SISO)", decodeTokensPerSec: 48.2),
            thermal: .fair,
            completedSteps: 4
        ),
        onStop: {}
    )
}
#endif
