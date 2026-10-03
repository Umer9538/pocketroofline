import SwiftUI

/// The shareable summary image. Laid out at 360 × 450 pt and rendered at 3×, giving 1080 × 1350 px.
struct ResultCard: View {
    static let size = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3

    let capture: Capture
    let headline: Headline
    /// The SILO part of the live curve: the sustained-load story in one line.
    let siloCurve: [LivePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("POCKETROOFLINE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .kerning(2)
                .foregroundStyle(RegimeLabel.silo.color)

            Text(capture.device.model)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.top, 14)
            Text("\(capture.device.soc) · \(capture.os.name) \(capture.os.version) (\(capture.os.build))")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            Text(headline.speeds)
                .font(.metric(34))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.top, 22)
            Text(headline.dropSummary)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(headline.hottest.color)
                .padding(.top, 2)

            if !siloCurve.isEmpty {
                DecodeCurveChart(points: siloCurve, showsAxes: false)
                    .frame(height: 110)
                    .padding(.top, 18)
            }

            Spacer(minLength: 12)

            Text(conditionsLine)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 6)
            Text("Peak = SISO mean · sustained = final SILO repeat")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Text(footer)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .foregroundStyle(.white)
        .background {
            LinearGradient(
                colors: [Color(white: 0.11), Color(white: 0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .environment(\.colorScheme, .dark)
    }

    private var conditionsLine: String {
        let conditions = capture.conditions
        return [
            capture.thermalAtStart.flatMap { start in
                capture.thermalAtEnd.map { "Thermal \(start.rawValue) → \($0.rawValue)" }
            },
            conditions.charging.map { $0 ? "plugged in" : "on battery" },
            conditions.airplaneMode ? "offline" : "network on",
            conditions.lowPowerMode ? "Low Power Mode" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private var footer: String {
        if DeviceProfile.isSimulator {
            return "iOS Simulator on a Mac, not phone data · TinyLlama 1.1B \(capture.model.quant) · llama.cpp CPU"
        }
        let backend = capture.backend.name == "llama.cpp-metal" ? "llama.cpp Metal" : "llama.cpp CPU"
        return "Measured on-device · TinyLlama 1.1B \(capture.model.quant) · \(backend) · pocketroofline"
    }

    @MainActor
    func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = Self.renderScale
        return renderer.uiImage
    }
}

#if DEBUG
#Preview {
    if let headline = Headline(capture: PreviewFixtures.capture) {
        ResultCard(
            capture: PreviewFixtures.capture,
            headline: headline,
            siloCurve: PreviewFixtures.livePoints.filter { $0.regime == .silo }
        )
    }
}
#endif
