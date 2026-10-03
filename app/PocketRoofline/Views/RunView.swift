import SwiftUI

/// The live view while a run is in progress.
struct RunView: View {
    @Environment(BenchmarkSession.self) private var session
    @Environment(DeviceConditions.self) private var conditions
    @State private var isConfirmingStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                stageTitle
                Spacer()
                ThermalChip(level: conditions.thermal)
            }

            currentSpeed

            DecodeCurveChart(points: session.livePoints)
                .frame(maxHeight: .infinity)
                .overlay {
                    if session.livePoints.isEmpty {
                        Text(waitingMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

            progress

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
    }

    private var stageTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stage.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text(stage.subtitle)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)
        }
        .animation(.default, value: stage.title)
    }

    private var currentSpeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.latestTokensPerSecond.map(Format.tokensPerSecond) ?? "––")
                .font(.metric(76))
                .contentTransition(.numericText())
                .animation(.snappy, value: session.latestTokensPerSecond)
            Text("tok/s decode, live")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(
                value: Double(session.completedRepeatCount),
                total: Double(BenchmarkProtocol.totalRepeats)
            )
            .tint(stage.tint)
            Text("Keep PocketRoofline open. Switching apps or locking the screen stops the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var waitingMessage: String {
        session.phase == .preparing ? "Loading model…" : "Warming up (not recorded)…"
    }

    private var stage: (title: String, subtitle: String, tint: Color) {
        switch session.phase {
        case .running(let regime, let repeatNumber):
            let spec = BenchmarkProtocol.regimes.first { $0.label == regime }
            let tokens = spec.map { " · \($0.promptTokens)→\($0.generateTokens)" } ?? ""
            return (
                "\(regime.rawValue) · \(repeatNumber) of \(BenchmarkProtocol.repeatsPerRegime)",
                regime.summary + tokens,
                regime.color
            )
        case .warmup:
            return ("Warming up", "One unrecorded pass", .secondary)
        default:
            return ("Preparing", "Loading the model into memory", .secondary)
        }
    }
}

#if DEBUG
#Preview {
    let conditions = DeviceConditions()
    let store = ModelStore()
    RunView()
        .environment(conditions)
        .environment(BenchmarkSession(modelStore: store, conditions: conditions))
}
#endif
