import SwiftUI

/// The run screen. It reads only `session.screen`, which changes between repeats and never while
/// one measures, so the GPU does nothing but decode during a repeat. There are no animations: each
/// update lands in a single redraw inside the 3 s pause.
struct RunView: View {
    @Environment(BenchmarkSession.self) private var session
    @State private var isConfirmingStop = false

    var body: some View {
        let screen = session.screen
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                stageTitle(screen.stage)
                Spacer()
                ThermalChip(level: screen.thermal)
            }

            lastRepeatSpeed(screen.lastRepeatDecodeTokensPerSecond)

            DecodeCurveChart(points: screen.points)
                .frame(maxHeight: .infinity)
                .overlay {
                    if screen.points.isEmpty {
                        Text(waitingMessage(screen.stage))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

            progress(screen)

            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                isConfirmingStop = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .confirmationDialog("Stop the run?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                Button("Stop and discard", role: .destructive, action: session.stop)
            } message: {
                Text("A partial run isn't saved.")
            }
        }
        .padding(20)
        .transaction { $0.animation = nil }
    }

    private func stageTitle(_ stage: BenchmarkSession.Screen.Stage) -> some View {
        let text = title(stage)
        return VStack(alignment: .leading, spacing: 2) {
            Text(text.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(text.subtitle)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)
        }
    }

    private func lastRepeatSpeed(_ tokensPerSecond: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tokensPerSecond.map(Format.tokensPerSecond) ?? "––")
                .font(.metric(76))
            Text("tok/s decode, last repeat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func progress(_ screen: BenchmarkSession.Screen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(
                value: Double(screen.completedRepeats),
                total: Double(BenchmarkProtocol.totalRepeats)
            )
            .tint(title(screen.stage).tint)
            Text("The screen holds still on purpose while a repeat measures; it updates between repeats.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Keep PocketRoofline open. Switching apps or locking the screen stops the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func waitingMessage(_ stage: BenchmarkSession.Screen.Stage) -> String {
        switch stage {
        case .preparing: "Loading model…"
        case .repeatUp: "Unrecorded warmup, then the first repeat.\nThe curve appears once it finishes."
        }
    }

    private func title(_ stage: BenchmarkSession.Screen.Stage) -> (title: String, subtitle: String, tint: Color) {
        switch stage {
        case .repeatUp(let regime, let repeatNumber):
            let spec = BenchmarkProtocol.regimes.first { $0.label == regime }
            let tokens = spec.map { " · \($0.promptTokens)→\($0.generateTokens)" } ?? ""
            return (
                "\(regime.rawValue) · \(repeatNumber) of \(BenchmarkProtocol.repeatsPerRegime)",
                regime.summary + tokens,
                regime.color
            )
        case .preparing:
            return ("Preparing", "Loading the model into memory", .secondary)
        }
    }
}

#if DEBUG
#Preview {
    let conditions = DeviceConditions()
    let store = ModelStore()
    RunView()
        .environment(BenchmarkSession(modelStore: store, conditions: conditions))
}
#endif
