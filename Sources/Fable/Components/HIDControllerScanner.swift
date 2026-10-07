import Foundation
import IOKit.hid

/// Finds game controllers that macOS's GameController framework doesn't report.
///
/// `GCController.controllers()` only lists devices macOS classifies as game
/// controllers, which it decides from the device's own HID usage. A pad that
/// advertises itself as something else is invisible there — and the 2026 Steam
/// Controller does exactly that: over Bluetooth it reports usage page 1, usage
/// **2 (Mouse)**, because it ships in the mouse-and-keyboard emulation mode
/// Valve's hardware has always used until software switches it to native
/// gamepad reports.
///
/// The consequence is bigger than a missing row in Fable's UI. Wine filters on
/// the same property, which is why its logs say `Ignoring HID device … not a
/// joystick or gamepad` — so a controller in this state is invisible to games
/// too, not merely to Fable.
///
/// This scanner exists to tell the user that honestly, rather than showing "No
/// controller detected" next to a pad that is plainly connected. It cannot fix
/// the underlying mode; only software speaking the vendor's protocol (Steam,
/// in practice) can do that.
enum HIDControllerScanner {

    struct Device: Equatable, Identifiable {
        let name: String
        let vendorID: Int
        let productID: Int
        /// True when the device declares itself a joystick or gamepad, so
        /// macOS and Wine will both route it as one.
        let presentsAsGamepad: Bool

        var id: String { "\(vendorID):\(productID):\(name)" }
    }

    /// HID usage page 1 — Generic Desktop. Everything below is within it.
    private static let genericDesktop = 1
    private static let joystickUsage = 4
    private static let gamepadUsage = 5
    private static let multiAxisUsage = 8

    /// Vendors whose pads are worth reporting even when they present as
    /// something other than a gamepad. Kept narrow on purpose: matching every
    /// mouse on the machine would make the panel actively misleading.
    private static let controllerVendors: Set<Int> = [
        0x28DE,   // Valve — Steam Controller, incl. the 2026 model (0x1303)
    ]

    /// Every HID device that is, or plausibly is, a game controller.
    static func scan() -> [Device] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        return devices.compactMap(describe).sorted { $0.name < $1.name }
    }

    private static func describe(_ device: IOHIDDevice) -> Device? {
        guard let vendorID = intProperty(device, kIOHIDVendorIDKey) else { return nil }
        let usagePage = intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        let presentsAsGamepad = usagePage == genericDesktop
            && [joystickUsage, gamepadUsage, multiAxisUsage].contains(usage)

        // Report a real gamepad whoever made it; otherwise only the vendors
        // known to ship pads that disguise themselves.
        guard presentsAsGamepad || controllerVendors.contains(vendorID) else { return nil }

        return Device(
            name: stringProperty(device, kIOHIDProductKey) ?? "Unknown controller",
            vendorID: vendorID,
            productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
            presentsAsGamepad: presentsAsGamepad
        )
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
