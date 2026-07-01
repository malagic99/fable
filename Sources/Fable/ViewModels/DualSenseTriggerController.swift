import GameController

/// Drives DualSense adaptive triggers via Apple's GameController framework.
/// Validated on hardware over USB + Bluetooth, and confirmed to coexist with
/// Wine/SDL holding the same pad for game input.
///
/// The plain-float trigger setters aren't in GameController's Swift overlay, so
/// we bridge to the ObjC selectors (which exist) via an `@objc` protocol and
/// `AnyObject` dynamic dispatch. See memory: fable-dualsense-triggers.
@objc private protocol DSAdaptiveTrigger {
    @objc optional func setModeWeapon(withStartPosition s: Float, endPosition e: Float, resistiveStrength r: Float)
    @objc optional func setModeFeedback(withStartPosition s: Float, resistiveStrength r: Float)
    @objc optional func setModeVibration(withStartPosition s: Float, amplitude a: Float, frequency f: Float)
    @objc optional func setModeOff()
}

@MainActor
final class DualSenseTriggerController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isDualSense = false
    /// Live trigger pull 0…1, for the config UI's readout.
    @Published private(set) var leftValue: Float = 0
    @Published private(set) var rightValue: Float = 0

    private weak var dualsense: GCDualSenseGamepad?
    private var applied: TriggerProfile = .off

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(connect(_:)), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(disconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
        GCController.startWirelessControllerDiscovery {}
        GCController.controllers().first.map { attach($0) }
    }

    @objc private func connect(_ note: Notification) { (note.object as? GCController).map { attach($0) } }
    @objc private func disconnect(_ note: Notification) {
        isConnected = false; isDualSense = false; dualsense = nil; leftValue = 0; rightValue = 0
    }

    private func attach(_ controller: GCController) {
        isConnected = true
        guard let ds = controller.physicalInputProfile as? GCDualSenseGamepad else { isDualSense = false; return }
        isDualSense = true
        dualsense = ds
        ds.leftTrigger.valueChangedHandler = { [weak self] _, v, _ in Task { @MainActor in self?.leftValue = v } }
        ds.rightTrigger.valueChangedHandler = { [weak self] _, v, _ in Task { @MainActor in self?.rightValue = v } }
        write(applied)  // re-apply the active profile to a freshly-connected pad
    }

    /// Applies a profile to the pad (and remembers it, so a reconnect re-applies).
    func apply(_ profile: TriggerProfile) {
        applied = profile
        write(profile)
    }

    /// Clears both triggers.
    func reset() { apply(.off) }

    private func write(_ profile: TriggerProfile) {
        guard let ds = dualsense else { return }
        set(ds.leftTrigger, profile.left)
        set(ds.rightTrigger, profile.right)
    }

    private func set(_ trigger: GCDualSenseAdaptiveTrigger, _ effect: TriggerEffect) {
        let t = trigger as AnyObject
        switch effect.mode {
        case .off:
            t.setModeOff?()
        case .feedback:
            t.setModeFeedback?(withStartPosition: effect.start, resistiveStrength: effect.strength)
        case .weapon:
            t.setModeWeapon?(withStartPosition: effect.start,
                             endPosition: max(effect.end, effect.start + 0.05),
                             resistiveStrength: effect.strength)
        case .vibration:
            t.setModeVibration?(withStartPosition: effect.start, amplitude: effect.amplitude, frequency: effect.frequency)
        }
    }
}
