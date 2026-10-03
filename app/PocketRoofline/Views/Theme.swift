import SwiftUI

extension ThermalLevel {
    var color: Color {
        switch self {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }
}

extension RegimeLabel {
    var color: Color {
        switch self {
        case .siso: .cyan
        case .liso: .purple
        case .silo: .mint
        }
    }
}

extension Font {
    /// Rounded, tabular figures, so live numbers don't jitter as digits change.
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    func cardBackground() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 20, style: .continuous))
    }
}

enum Format {
    static func tokensPerSecond(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func megabytes(_ bytes: Int64) -> String {
        Measurement(value: Double(bytes) / 1_000_000, unit: UnitInformationStorage.megabytes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
