import SwiftUI

struct ThermalChip: View {
    let level: ThermalLevel

    var body: some View {
        Label(level.displayName, systemImage: "thermometer.medium")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.18), in: .capsule)
            .animation(.easeInOut(duration: 0.4), value: level)
            .accessibilityLabel("Thermal state \(level.displayName)")
    }
}

#Preview {
    VStack {
        ForEach(ThermalLevel.allCases, id: \.self, content: ThermalChip.init)
    }
    .padding()
}
