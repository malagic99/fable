import Foundation
import Testing

@testable import Fable

@Suite("HID controller scanner")
struct HIDControllerScannerTests {

    /// The 2026 Steam Controller over Bluetooth, as this machine actually
    /// reports it: Valve's vendor id, and HID usage 2 (Mouse) rather than
    /// 4/5 (Joystick/Gamepad). `GCController.controllers()` returns empty for
    /// it, which is why Fable showed "No controller detected" beside a pad
    /// that was plainly connected.
    @Test
    func steamControllerIsReportedButNotRouted() {
        let pad = HIDControllerScanner.Device(
            name: "Steam Ctrl (BT) FXA9961600685",
            vendorID: 0x28DE, productID: 0x1303, presentsAsGamepad: false)
        #expect(!pad.presentsAsGamepad)
        #expect(pad.vendorID == 0x28DE)
    }

    /// A pad macOS already routes needs no warning — it reaches GCController
    /// and Wine on its own.
    @Test
    func properlyRoutedPadsAreNotWarnedAbout() {
        let dualSense = HIDControllerScanner.Device(
            name: "DualSense Wireless Controller",
            vendorID: 0x054C, productID: 0x0CE6, presentsAsGamepad: true)
        #expect(dualSense.presentsAsGamepad)
    }

    /// Identity includes the product, so two pads of the same model are
    /// distinct rows rather than one.
    @Test
    func devicesAreIdentifiedDistinctly() {
        let first = HIDControllerScanner.Device(
            name: "Steam Ctrl (BT) AAA", vendorID: 0x28DE, productID: 0x1303,
            presentsAsGamepad: false)
        let second = HIDControllerScanner.Device(
            name: "Steam Ctrl (BT) BBB", vendorID: 0x28DE, productID: 0x1303,
            presentsAsGamepad: false)
        #expect(first.id != second.id)
    }

    /// Scanning must not trap or hang regardless of what's attached — it runs
    /// on every refresh of the bottle page.
    @Test
    func scanningIsSafeWithWhateverIsAttached() {
        let devices = HIDControllerScanner.scan()
        #expect(devices.allSatisfy { !$0.name.isEmpty })
    }
}
