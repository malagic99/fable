import Foundation
import Testing
@testable import Fable

/// The architecture seam: Mach-O header reading and the Wine dispatch-directory
/// layout derived from it. See docs/FEX-MIGRATION.md.
@Suite struct WineLayoutTests {

    // MARK: Mach-O headers

    /// Thin 64-bit Mach-O: MH_MAGIC_64 little-endian, then cputype.
    private func thinHeader(cpuType: UInt32) -> Data {
        var bytes: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
        for shift in stride(from: 0, through: 24, by: 8) {
            bytes.append(UInt8((cpuType >> UInt32(shift)) & 0xFF))
        }
        return Data(bytes + [UInt8](repeating: 0, count: 24))
    }

    /// Fat header: FAT_MAGIC + nfat_arch + 20-byte fat_arch entries, all
    /// big-endian.
    private func fatHeader(cpuTypes: [UInt32]) -> Data {
        var bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        func appendBE(_ value: UInt32) {
            bytes.append(contentsOf: [
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
            ])
        }
        appendBE(UInt32(cpuTypes.count))
        for cpuType in cpuTypes {
            appendBE(cpuType)
            bytes.append(contentsOf: [UInt8](repeating: 0, count: 16))  // rest of fat_arch
        }
        return Data(bytes)
    }

    @Test
    func readsThinArchitectures() {
        #expect(MachOInfo.architecture(of: thinHeader(cpuType: 0x0100_0007)) == .x86_64)
        #expect(MachOInfo.architecture(of: thinHeader(cpuType: 0x0100_000C)) == .arm64)
        // Unknown cputype and 32-bit/garbage magic are both "don't know".
        #expect(MachOInfo.architecture(of: thinHeader(cpuType: 0x0000_0007)) == nil)
        #expect(MachOInfo.architecture(of: Data([0xCE, 0xFA, 0xED, 0xFE, 0, 0, 0, 0])) == nil)
        #expect(MachOInfo.architecture(of: Data()) == nil)
    }

    @Test
    func readsFatArchitectures() {
        #expect(MachOInfo.architecture(of: fatHeader(cpuTypes: [0x0100_0007, 0x0100_000C]))
                == .universal(hasARM64: true))
        #expect(MachOInfo.architecture(of: fatHeader(cpuTypes: [0x0100_0007]))
                == .universal(hasARM64: false))
    }

    @Test
    func onlyIntelOnlyBinariesNeedRosetta() {
        #expect(MachOInfo.Architecture.x86_64.needsRosetta)
        #expect(!MachOInfo.Architecture.arm64.needsRosetta)
        // A fat binary with an arm64 slice runs native — the loader prefers it.
        #expect(!MachOInfo.Architecture.universal(hasARM64: true).needsRosetta)
        #expect(MachOInfo.Architecture.universal(hasARM64: false).needsRosetta)
    }

    // MARK: Layout

    @Test
    func rosettaLayoutIsTodaysShape() {
        #expect(WineLayout.rosetta.unixDirectory == "x86_64-unix")
        #expect(WineLayout.rosetta.peDirectory == "x86_64-windows")
        #expect(WineLayout.rosetta.isTranslatedHost)
    }

    @Test
    func nativeLayoutMovesOnlyTheUnixSide() {
        // The guest stays Windows x86-64 in both worlds — only the host half
        // changes architecture. Getting this backwards is the whole trap.
        #expect(WineLayout.nativeARM64.unixDirectory == "aarch64-unix")
        #expect(WineLayout.nativeARM64.peDirectory == WineLayout.rosetta.peDirectory)
        #expect(!WineLayout.nativeARM64.isTranslatedHost)
    }

    @Test
    func detectionFallsBackToRosettaWhenTheBinaryIsUnreadable() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Missing file, and a file that isn't a Mach-O at all.
        #expect(WineLayout.detect(wineBinary: dir.appending(path: "nope")) == .rosetta)
        let notMachO = dir.appending(path: "wine")
        try Data("#!/bin/sh\n".utf8).write(to: notMachO)
        #expect(WineLayout.detect(wineBinary: notMachO) == .rosetta)
    }

    @Test
    func detectionReadsRealBinaries() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let intel = dir.appending(path: "wine-intel")
        try thinHeader(cpuType: 0x0100_0007).write(to: intel)
        #expect(WineLayout.detect(wineBinary: intel) == .rosetta)

        let native = dir.appending(path: "wine-arm64")
        try thinHeader(cpuType: 0x0100_000C).write(to: native)
        #expect(WineLayout.detect(wineBinary: native) == .nativeARM64)
    }

    // MARK: The env-var gate

    @Test
    func rosettaOnlyVarsAreSetOnlyForATranslatedHost() {
        let prefix = URL(fileURLWithPath: "/tmp/prefix")
        let translated = WineEnv.base(prefix: prefix, layout: .rosetta)
        let native = WineEnv.base(prefix: prefix, layout: .nativeARM64)

        #expect(translated[WineEnv.advertiseAVX.key] == WineEnv.advertiseAVX.value)
        #expect(native[WineEnv.advertiseAVX.key] == nil)

        // Everything else is architecture-independent and must not move.
        #expect(translated[WineEnv.prefix] == native[WineEnv.prefix])
        #expect(native["SDL_JOYSTICK_HIDAPI_PS5"] == "1")
        #expect(native["DOTNET_SYSTEM_GLOBALIZATION_USENLS"] == "1")
    }

    @Test
    func defaultsPreserveTodaysBehavior() {
        // Every existing call site omits `layout` — it must keep getting the
        // Rosetta environment, AVX flag and all.
        let prefix = URL(fileURLWithPath: "/tmp/prefix")
        #expect(WineEnv.base(prefix: prefix) == WineEnv.base(prefix: prefix, layout: .rosetta))
        #expect(WineEnv.provisioning(prefix: prefix)[WineEnv.advertiseAVX.key]
                == WineEnv.advertiseAVX.value)
    }

    // MARK: Diagnostics

    @Test
    func diagnosticSummaryNamesTheWorld() {
        #expect(WineLayout.rosetta.diagnosticSummary.contains("Rosetta"))
        #expect(WineLayout.nativeARM64.diagnosticSummary.contains("native"))
    }
}
