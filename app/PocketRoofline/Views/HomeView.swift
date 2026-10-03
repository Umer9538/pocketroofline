import SwiftUI

struct HomeView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(DeviceConditions.self) private var conditions
    @Environment(BenchmarkSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let outcome = OutcomeBanner(phase: session.phase) {
                    outcome
                }
                ModelCard()
                PreRunChecklist()
                runButton
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PocketRoofline")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Measures how fast this iPhone runs a small language model, and how much it slows as it heats up. Every number comes from this device.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var runButton: some View {
        VStack(spacing: 10) {
            Button {
                session.start()
            } label: {
                Label("Run benchmark", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(modelStore.verifiedFile == nil)

            Text("Takes about 5 minutes. Keep the app open: leaving it stops the run.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Explains how the previous run ended when it didn't produce a result.
private struct OutcomeBanner: View {
    let title: String
    let message: String
    let systemImage: String

    init?(phase: BenchmarkSession.Phase) {
        switch phase {
        case .interrupted(.leftForeground):
            title = "Run stopped"
            message = "PocketRoofline left the foreground. iOS doesn't allow GPU work in the background, so the partial run was discarded. Keep the app open for the whole run."
            systemImage = "rectangle.portrait.and.arrow.right"
        case .interrupted(.stoppedByUser):
            title = "Run stopped"
            message = "Nothing was saved."
            systemImage = "stop.circle"
        case .failed(let reason):
            title = "Run failed"
            message = reason
            systemImage = "exclamationmark.triangle"
        case .idle, .preparing, .warmup, .running, .finished:
            return nil
        }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.orange)
        }
        .cardBackground()
    }
}

#if DEBUG
#Preview {
    let conditions = DeviceConditions()
    let store = ModelStore()
    HomeView()
        .environment(store)
        .environment(conditions)
        .environment(BenchmarkSession(modelStore: store, conditions: conditions))
}
#endif
