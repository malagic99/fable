import Foundation
import Testing
@testable import Fable

/// Raw DualSense output reports — the bytes that carry trigger effects past
/// GameController's background-write gate. Layout per SDL's PS5 driver +
/// Nielk1/DS4Windows effect encoding.
@Suite struct DualSenseReportTests {

    @Test
    func crc32MatchesTheStandardCheckValue() {
        // The canonical CRC-32 check: crc32("123456789") == 0xCBF43926.
        #expect(DualSenseReport.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test
    func offEffectIsAReset() {
        let bytes = DualSenseReport.effectBytes(TriggerEffect(mode: .off))
        #expect(bytes.count == 11)
        #expect(bytes[0] == 0x05)
        #expect(bytes.dropFirst().allSatisfy { $0 == 0 })
    }

    @Test
    func feedbackFromZeroCoversAllTenZones() {
        // start 0, full strength → mode 0x21, all zones active, force 7 packed
        // 3-bit into every zone.
        let bytes = DualSenseReport.effectBytes(
            TriggerEffect(mode: .feedback, start: 0, strength: 1.0)
        )
        #expect(bytes[0] == 0x21)
        let active = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        #expect(active == 0x03FF)  // all 10 zones
        var expectedForce: UInt32 = 0
        for i in 0...9 { expectedForce |= 7 << (3 * i) }
        let force = UInt32(bytes[3]) | (UInt32(bytes[4]) << 8)
            | (UInt32(bytes[5]) << 16) | (UInt32(bytes[6]) << 24)
        #expect(force == expectedForce)
    }

    @Test
    func weaponEncodesStartEndStrength() {
        // start 0.35 → zone 3, end 0.7 → zone 6, strength 1.0 → level 8.
        let bytes = DualSenseReport.effectBytes(
            TriggerEffect(mode: .weapon, start: 0.35, end: 0.7, strength: 1.0)
        )
        #expect(bytes[0] == 0x25)
        let zones = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        #expect(zones == (1 << 3) | (1 << 6))
        #expect(bytes[3] == 7)  // strength level 8 → 7 on the wire
    }

    @Test
    func zeroStrengthFallsBackToReset() {
        let feedback = DualSenseReport.effectBytes(
            TriggerEffect(mode: .feedback, start: 0.2, strength: 0)
        )
        #expect(feedback[0] == 0x05)
    }

    @Test
    func usbReportSetsOnlyTriggerFlags() {
        let report = DualSenseReport.usbReport(.shooter)
        #expect(report.count == 48)
        #expect(report[0] == 0x02)
        #expect(report[1] == 0x0C)               // trigger flags only…
        #expect(report[2] == 0x00)               // …no flag1 bits
        #expect(report[3] == 0 && report[4] == 0)  // rumble untouched
        // Right trigger effect lands at payload+10 (absolute 11).
        #expect(report[11] == DualSenseReport.effectBytes(TriggerProfile.shooter.right)[0])
        // Left at payload+21 (absolute 22).
        #expect(report[22] == DualSenseReport.effectBytes(TriggerProfile.shooter.left)[0])
    }

    @Test
    func btReportIsSealedWithACRCThePadWillAccept() {
        let report = DualSenseReport.btReport(.shooter)
        #expect(report.count == 78)
        #expect(report[0] == 0x31)
        #expect(report[1] == 0x02)
        #expect(report[2] == 0x0C)
        // Effects shifted by the 2-byte BT header: right at 12, left at 23.
        #expect(report[12] == DualSenseReport.effectBytes(TriggerProfile.shooter.right)[0])
        #expect(report[23] == DualSenseReport.effectBytes(TriggerProfile.shooter.left)[0])
        // The trailing CRC-32 must cover 0xA2 + the first 74 bytes.
        let expected = DualSenseReport.crc32([0xA2] + report[0..<74])
        let stored = UInt32(report[74]) | (UInt32(report[75]) << 8)
            | (UInt32(report[76]) << 16) | (UInt32(report[77]) << 24)
        #expect(stored == expected)
    }
}
