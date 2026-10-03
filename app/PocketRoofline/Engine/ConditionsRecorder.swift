import Foundation

/// Accumulates run conditions from samples taken throughout a run, resolving each one
/// conservatively: a favourable condition is only claimed if it held at every sample.
@MainActor
struct ConditionsRecorder {
    private let conditions: DeviceConditions
    private var batteryStartPercent: Double?
    private var batteryEndPercent: Double?
    private var everOnExternalPower = false
    private var powerStateKnownAtEverySample = true
    private var everInLowPowerMode = false
    private var offlineAtEverySample = true
    private var sampleCount = 0

    init(conditions: DeviceConditions) {
        self.conditions = conditions
    }

    mutating func sample() {
        conditions.refresh()
        if sampleCount == 0 { batteryStartPercent = conditions.batteryPercent }
        batteryEndPercent = conditions.batteryPercent
        if let onExternalPower = conditions.isOnExternalPower {
            everOnExternalPower = everOnExternalPower || onExternalPower
        } else {
            powerStateKnownAtEverySample = false
        }
        everInLowPowerMode = everInLowPowerMode || conditions.isLowPowerModeEnabled
        // An unknown path (no update yet) can't prove the radios were off.
        offlineAtEverySample = offlineAtEverySample && conditions.hasNetworkPath == false
        sampleCount += 1
    }

    /// `airplaneMode` is inferred: iOS has no airplane-mode API, so it means "no usable network
    /// path at any sample", which is what matters for radio-induced noise.
    var result: Capture.Conditions {
        Capture.Conditions(
            // Plugged in at any sample is a fact; "unplugged" needs every sample to agree.
            charging: everOnExternalPower ? true : (powerStateKnownAtEverySample ? false : nil),
            airplaneMode: sampleCount > 0 && offlineAtEverySample,
            batteryStartPct: batteryStartPercent,
            batteryEndPct: batteryEndPercent,
            lowPowerMode: everInLowPowerMode
        )
    }
}
