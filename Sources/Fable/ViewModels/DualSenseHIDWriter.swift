import Foundation
import IOKit.hid

/// Writes trigger effects to the DualSense over raw HID, bypassing the
/// GameController framework — which silently drops output writes while the app
/// is backgrounded, i.e. the instant a game window takes focus. Raw HID output
/// has no such focus gate, and the coexistence spike proved a raw HID session
/// and GameController can hold the same pad simultaneously.
///
/// All calls happen on the main run loop (the manager is scheduled there and
/// the trigger controller is @MainActor).
final class DualSenseHIDWriter {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var isBluetooth = false

    init() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = DualSenseReport.productIDs.map {
            [kIOHIDVendorIDKey: DualSenseReport.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DualSenseHIDWriter>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let writer = Unmanaged<DualSenseHIDWriter>.fromOpaque(context).takeUnretainedValue()
            if writer.device == device { writer.device = nil }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Pick up a pad that was already connected before Fable started.
        if let devices = IOHIDManagerCopyDevices(manager) as NSSet?,
           let existing = devices.anyObject() {
            attach(existing as! IOHIDDevice)
        }
    }

    private func attach(_ device: IOHIDDevice) {
        self.device = device
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        // Anything that isn't USB (Bluetooth/BT/…) needs the CRC-sealed report.
        isBluetooth = !transport.uppercased().contains("USB")
    }

    /// True when a DualSense is reachable over raw HID.
    var isReady: Bool { device != nil }

    /// Sends the profile straight to the pad. Returns false when no device is
    /// attached or the write fails (caller falls back to GameController).
    @discardableResult
    func write(_ profile: TriggerProfile) -> Bool {
        guard let device else { return false }
        let report = isBluetooth ? DualSenseReport.btReport(profile)
                                 : DualSenseReport.usbReport(profile)
        let status = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(report[0]),
                buffer.baseAddress!, buffer.count
            )
        }
        return status == kIOReturnSuccess
    }
}
