import SwiftUI

/// Download, verification, and readiness of the pinned benchmark model.
struct ModelCard: View {
    @Environment(ModelStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.model.displayName) · \(store.model.quant)")
                        .font(.headline)
                    Text("Fixed model, so every phone runs identical weights")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.megabytes(store.model.sizeBytes))
                    .font(.metric(15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            status
        }
        .cardBackground()
        .animation(.default, value: store.state)
    }

    @ViewBuilder
    private var status: some View {
        switch store.state {
        case .checking:
            ProgressView().frame(maxWidth: .infinity, alignment: .leading)

        case .absent:
            Button("Download model", systemImage: "arrow.down.circle.fill", action: store.download)
                .buttonStyle(.bordered)

        case .downloading(let received, let expected):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(received), total: Double(max(expected, 1)))
                HStack {
                    Text("\(Format.megabytes(received)) of \(Format.megabytes(expected))")
                        .font(.metric(13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel, action: store.cancelDownload)
                        .font(.footnote)
                }
            }

        case .verifying:
            Label {
                Text("Verifying SHA-256…")
            } icon: {
                ProgressView()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        case .ready(_, let sha256):
            Label {
                Text("Verified · SHA-256 \(sha256.prefix(12))…")
                    .font(.system(.subheadline, design: .monospaced))
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Button("Try again", systemImage: "arrow.clockwise", action: store.download)
                    .buttonStyle(.bordered)
            }
        }
    }
}
