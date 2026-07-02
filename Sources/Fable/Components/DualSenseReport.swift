import Foundation

/// Builds raw DualSense output reports that set the adaptive-trigger effects
/// directly over HID — bypassing the GameController framework, which silently
/// drops output writes while the app is backgrounded (i.e. the moment a game
/// window takes focus). Byte layout follows SDL's HIDAPI PS5 driver and the
/// community-standard trigger-effect encoding (Nielk1/DS4Windows), the same
/// bytes Steam Input sends.
///
/// Only the two trigger-effect flags are ever set — rumble, LEDs, and audio
/// flags stay zero so we never stomp state another writer (the game, Steam)
/// owns.
enum DualSenseReport {

    /// Sony vendor + DualSense / DualSense Edge products, for HID matching.
    static let vendorID = 0x054C
    static let productIDs = [0x0CE6, 0x0DF2]

    // MARK: Trigger effect block (11 bytes: mode + 10 params)

    /// One trigger's 11-byte effect block.
    static func effectBytes(_ effect: TriggerEffect) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 11)
        switch effect.mode {
        case .off:
            b[0] = 0x05  // reset / no resistance
        case .feedback:
            // Constant resistance from a start position: 10 zones, 3-bit force.
            let position = zone(effect.start, 0...9)
            let strength = level(effect.strength)
            guard strength > 0 else { b[0] = 0x05; break }
            let force = UInt32(strength - 1) & 0x07
            var forceZones: UInt32 = 0
            var activeZones: UInt16 = 0
            for i in position...9 {
                forceZones |= force << (3 * i)
                activeZones |= 1 << i
            }
            b[0] = 0x21
            b[1] = UInt8(activeZones & 0xFF)
            b[2] = UInt8((activeZones >> 8) & 0xFF)
            b[3] = UInt8(forceZones & 0xFF)
            b[4] = UInt8((forceZones >> 8) & 0xFF)
            b[5] = UInt8((forceZones >> 16) & 0xFF)
            b[6] = UInt8((forceZones >> 24) & 0xFF)
        case .weapon:
            // Resistance wall between start and end, then release.
            let start = min(max(zone(effect.start, 2...7), 2), 7)
            let end = min(max(zone(effect.end, 2...8), start + 1), 8)
            let strength = level(effect.strength)
            guard strength > 0 else { b[0] = 0x05; break }
            let zones: UInt16 = (1 << start) | (1 << end)
            b[0] = 0x25
            b[1] = UInt8(zones & 0xFF)
            b[2] = UInt8((zones >> 8) & 0xFF)
            b[3] = UInt8(strength - 1)
        case .vibration:
            let position = zone(effect.start, 0...9)
            let amplitude = level(effect.amplitude)
            let frequency = UInt8(min(max(Int((effect.frequency * 255).rounded()), 1), 255))
            guard amplitude > 0 else { b[0] = 0x05; break }
            let amp = UInt32(amplitude - 1) & 0x07
            var amplitudeZones: UInt32 = 0
            var activeZones: UInt16 = 0
            for i in position...9 {
                amplitudeZones |= amp << (3 * i)
                activeZones |= 1 << i
            }
            b[0] = 0x26
            b[1] = UInt8(activeZones & 0xFF)
            b[2] = UInt8((activeZones >> 8) & 0xFF)
            b[3] = UInt8(amplitudeZones & 0xFF)
            b[4] = UInt8((amplitudeZones >> 8) & 0xFF)
            b[5] = UInt8((amplitudeZones >> 16) & 0xFF)
            b[6] = UInt8((amplitudeZones >> 24) & 0xFF)
            b[9] = frequency
        }
        return b
    }

    // MARK: Full output reports

    /// USB output report (id 0x02, 48 bytes). Trigger flags only.
    static func usbReport(_ profile: TriggerProfile) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 48)
        report[0] = 0x02
        // payload[0] = valid_flag0: 0x04 right trigger, 0x08 left trigger.
        report[1] = 0x0C
        report.replaceSubrange(11..<22, with: effectBytes(profile.right))  // payload +10
        report.replaceSubrange(22..<33, with: effectBytes(profile.left))   // payload +21
        return report
    }

    /// Bluetooth output report (id 0x31, 78 bytes, CRC-32 sealed — the pad
    /// ignores BT output whose checksum doesn't match).
    static func btReport(_ profile: TriggerProfile) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 78)
        report[0] = 0x31
        report[1] = 0x02  // SDL's magic flag byte
        report[2] = 0x0C  // valid_flag0, payload starts at offset 2
        report.replaceSubrange(12..<23, with: effectBytes(profile.right))  // payload +10
        report.replaceSubrange(23..<34, with: effectBytes(profile.left))   // payload +21
        // CRC over the BT output seed byte 0xA2 + the first 74 report bytes.
        let crc = crc32([0xA2] + report[0..<74])
        report[74] = UInt8(crc & 0xFF)
        report[75] = UInt8((crc >> 8) & 0xFF)
        report[76] = UInt8((crc >> 16) & 0xFF)
        report[77] = UInt8((crc >> 24) & 0xFF)
        return report
    }

    /// Standard CRC-32 (zlib polynomial, reflected).
    static func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB88320 & (crc & 1 == 1 ? 0xFFFFFFFF : 0))
            }
        }
        return ~crc
    }

    // MARK: Scaling

    /// 0…1 float → trigger zone index within `range`.
    private static func zone(_ value: Float, _ range: ClosedRange<Int>) -> Int {
        min(max(Int((value * 9).rounded()), range.lowerBound), range.upperBound)
    }

    /// 0…1 float → 8-level strength (0 = none).
    private static func level(_ value: Float) -> Int {
        guard value > 0 else { return 0 }
        return min(max(Int((value * 8).rounded()), 1), 8)
    }
}
