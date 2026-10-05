import SwiftUI

struct HomeView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(DeviceConditions.self) private var conditions
    @Environment(BenchmarkSession.self) private var session
    @Environment(DiagnosticSession.self) private var diagnostic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let outcome = OutcomeBanner(phase: session.phase) {
                    outcome
                }
                if let outcome = OutcomeBanner(diagnosticPhase: diagnostic.phase) {
                    outcome
                }
                ModelCard()
                PreRunChecklist()
                runButton
                diagnosticButton
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
                diagnostic.reset()  // clears a stale diagnostic banner
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

    /// Secondary on purpose: a diagnostic explains a slowdown and is never a benchmark result.
    private var diagnosticButton: some View {
        VStack(spacing: 8) {
            Button {
                diagnostic.start()
            } label: {
                Label("Diagnostic run (long test first, quiet screen)", systemImage: "stethoscope")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(modelStore.verifiedFile == nil)

            Text("Runs the long test first, from a cool phone, on a still screen. Saved separately, never mixed with benchmark results.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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

    init?(diagnosticPhase phase: DiagnosticSession.Phase) {
        switch phase {
        case .interrupted(.leftForeground):
            title = "Diagnostic run stopped"
            message = "PocketRoofline left the foreground, so the partial run was discarded. Keep the app open for the whole run."
            systemImage = "rectangle.portrait.and.arrow.right"
        case .interrupted(.stoppedByUser):
            title = "Diagnostic run stopped"
            message = "Nothing was saved."
            systemImage = "stop.circle"
        case .failed(let reason):
            title = "Diagnostic run failed"
            message = reason
            systemImage = "exclamationmark.triangle"
        case .idle, .running, .finished:
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
    let session = BenchmarkSession(modelStore: store, conditions: conditions)
    HomeView()
        .environment(store)
        .environment(conditions)
        .environment(session)
        .environment(DiagnosticSession(modelStore: store, conditions: conditions, benchmark: session))
}
#endif
