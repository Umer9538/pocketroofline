import SwiftUI
import UIKit

struct ResultView: View {
    let capture: Capture
    let savedTo: URL?
    let curve: [LivePoint]
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var cardImage: UIImage?
    @State private var pendingSubmission: Submission?
    @State private var submissionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let headline = Headline(capture: capture) {
                    HeadlineTiles(headline: headline)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Decode speed over the run").font(.headline)
                    DecodeCurveChart(points: curve).frame(height: 220)
                }
                .cardBackground()
                RepeatsTable(regimes: capture.regimes)
                actions
                Button("Done", action: onDone)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .task { renderCard() }
        .alert("Submit to the benchmark", isPresented: isPresenting($pendingSubmission), presenting: pendingSubmission) { submission in
            Button("Open GitHub") { openURL(submission.url) }
            Button("Cancel", role: .cancel) {}
        } message: { submission in
            Text(submission.embedsCapture
                ? "Your capture is pre-filled in the GitHub issue form, and also copied to the clipboard."
                : "JSON copied — paste it into the Capture field of the GitHub issue form.")
        }
        .alert("Couldn't prepare the capture", isPresented: isPresenting($submissionError), presenting: submissionError) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    private func isPresenting<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capture.device.model)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(capture.device.soc) · \(capture.device.ramGB) GB · \(capture.os.name) \(capture.os.version) (\(capture.os.build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let cardImage {
                let image = Image(uiImage: cardImage)
                ShareLink(item: image, preview: SharePreview("PocketRoofline · \(capture.device.model)", image: image)) {
                    Label("Share card", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if DeviceProfile.isSimulator {
                Label("Simulator run: llama.cpp on your Mac's CPU, not phone data, so it can't be submitted.", systemImage: "desktopcomputer")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Button(action: submit) {
                    Label("Submit to benchmark", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let savedTo {
                HStack(spacing: 12) {
                    ShareLink(item: savedTo) {
                        Label("Export JSON", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        openInFiles(savedTo)
                    } label: {
                        Label("Show in Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    private func renderCard() {
        guard let headline = Headline(capture: capture) else { return }
        cardImage = ResultCard(
            capture: capture,
            headline: headline,
            siloCurve: curve.filter { $0.regime == .silo }
        ).renderImage()
    }

    /// The capture always goes on the clipboard, because long captures don't fit in a URL.
    private func submit() {
        do {
            let submission = try Submission(capture: capture)
            UIPasteboard.general.string = submission.compactJSON
            pendingSubmission = submission
        } catch {
            submissionError = error.localizedDescription
        }
    }

    /// The `shareddocuments` scheme opens the Files app at a path inside this app's Documents.
    private func openInFiles(_ url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "shareddocuments"
        if let filesURL = components?.url {
            openURL(filesURL)
        }
    }
}

private struct HeadlineTiles: View {
    let headline: Headline

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headline.speeds)
                .font(.metric(38))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(headline.dropSummary)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(headline.hottest.color)
            HStack(spacing: 10) {
                tile("Peak", Format.tokensPerSecond(headline.peak), "SISO mean")
                tile("Sustained", Format.tokensPerSecond(headline.sustained), "final SILO repeat")
                tile("Drop", Format.percent(headline.dropPercent), "peak → sustained")
            }
        }
        .cardBackground()
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.metric(24))
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every repeat, as measured. Deliberately no per-regime means: SILO's mean is not a throughput.
private struct RepeatsTable: View {
    let regimes: [RegimeResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every repeat").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Run")
                    Text("Decode").gridColumnAlignment(.trailing)
                    Text("Prefill").gridColumnAlignment(.trailing)
                    Text("Thermal")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(regimes) { regime in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(regime.repeats) { repeatResult in
                        GridRow {
                            Text("\(regime.label.rawValue) \(repeatResult.index + 1)")
                                .foregroundStyle(regime.label.color)
                            Text(Format.tokensPerSecond(repeatResult.decodeTokensPerSec))
                            Text(repeatResult.prefillTokensPerSec.formatted(.number.precision(.fractionLength(0))))
                                .foregroundStyle(.secondary)
                            thermal(repeatResult)
                        }
                        .font(.metric(15, weight: .medium))
                    }
                }
            }
            Text("tok/s. Prefill and decode are timed separately with synthetic tokens.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    private func thermal(_ repeatResult: RepeatResult) -> some View {
        HStack(spacing: 4) {
            Circle().fill(repeatResult.thermalStateStart.color).frame(width: 7, height: 7)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Circle().fill(repeatResult.thermalStateEnd.color).frame(width: 7, height: 7)
            Text(repeatResult.thermalStateEnd.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal \(repeatResult.thermalStateStart.rawValue) to \(repeatResult.thermalStateEnd.rawValue)")
    }
}

#if DEBUG
#Preview {
    ResultView(
        capture: PreviewFixtures.capture,
        savedTo: nil,
        curve: PreviewFixtures.livePoints,
        onDone: {}
    )
}
#endif
