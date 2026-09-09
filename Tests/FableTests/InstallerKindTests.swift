import Foundation
import Testing
@testable import Fable

/// Classifying Windows installers, and the Wine command line each kind needs.
@Suite struct InstallerKindTests {

    /// OLE2 compound-document signature — what an MSI database starts with.
    private let oleHead = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
                               + [UInt8](repeating: 0, count: 56))

    /// Minimal PE32+ image: "MZ", e_lfanew at 0x3C, "PE\0\0" + magic 0x20B.
    private func peHead(magic: UInt16 = 0x20B) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D; bytes[1] = 0x5A                     // MZ
        bytes[0x3C] = 0x80                                   // e_lfanew = 0x80
        bytes[0x80] = 0x50; bytes[0x81] = 0x45               // "PE"
        bytes[0x80 + 24] = UInt8(magic & 0xFF)
        bytes[0x80 + 25] = UInt8(magic >> 8)
        return Data(bytes)
    }

    // MARK: Classification

    @Test
    func msiExtensionIsAPackage() {
        #expect(InstallerKind.detect(head: oleHead, pathExtension: "msi") == .msiPackage)
        #expect(InstallerKind.detect(head: oleHead, pathExtension: "MSI") == .msiPackage)
    }

    @Test
    func aTruncatedPackageStillRoutesToWindowsInstaller() {
        // Better to let msiexec say "this package could not be opened" than to
        // have Wine fail trying to exec a database.
        #expect(InstallerKind.detect(head: Data(), pathExtension: "msi") == .msiPackage)
    }

    @Test
    func anMSIWearingTheWrongExtensionIsCaughtBySignature() {
        #expect(InstallerKind.detect(head: oleHead, pathExtension: "bin") == .msiPackage)
    }

    @Test
    func executablesAreUnaffected() {
        #expect(InstallerKind.detect(head: peHead(), pathExtension: "exe") == .executable)
        #expect(InstallerKind.detect(head: peHead(magic: 0x10B), pathExtension: "exe") == .executable)
    }

    @Test
    func anythingUnrecognizedKeepsTodaysRunItBehavior() {
        // The conservative bias: a header we can't parse must never block an
        // install that used to work.
        #expect(InstallerKind.detect(head: Data(), pathExtension: "exe") == .executable)
        #expect(InstallerKind.detect(head: Data("#!/bin/sh\n".utf8), pathExtension: "") == .executable)
    }

    // MARK: Command line

    @Test
    func packagesGoThroughMsiexecByBareFilename() {
        // Bare filename + the caller's working directory: no unix→Windows path
        // translation, and sibling .cab files stay reachable.
        let url = URL(fileURLWithPath: "/Users/x/Downloads/Some Game.msi")
        #expect(GameInstaller.wineArguments(for: url, kind: .msiPackage)
                == ["msiexec", "/i", "Some Game.msi"])
    }

    @Test
    func executablesKeepTheirFullPath() {
        let url = URL(fileURLWithPath: "/Users/x/Downloads/setup.exe")
        #expect(GameInstaller.wineArguments(for: url, kind: .executable)
                == ["/Users/x/Downloads/setup.exe"])
    }

    @Test
    func extraArgumentsAreAppendedInBothShapes() {
        let msi = URL(fileURLWithPath: "/tmp/a.msi")
        #expect(GameInstaller.wineArguments(for: msi, kind: .msiPackage, extra: ["/qn"])
                == ["msiexec", "/i", "a.msi", "/qn"])
        let exe = URL(fileURLWithPath: "/tmp/a.exe")
        #expect(GameInstaller.wineArguments(for: exe, kind: .executable, extra: ["/S"])
                == ["/tmp/a.exe", "/S"])
    }

    // MARK: Exit codes

    @Test
    func documentedInstallerCodesGetPlainLanguage() {
        #expect(InstallerKind.msiExitMeaning(1602)?.contains("cancelled") == true)
        #expect(InstallerKind.msiExitMeaning(1618)?.contains("already running") == true)
        #expect(InstallerKind.msiExitMeaning(1619)?.contains("corrupt") == true)
        #expect(InstallerKind.msiExitMeaning(3010)?.contains("success") == true)
        // Undocumented codes fall through to the generic advice.
        #expect(InstallerKind.msiExitMeaning(42) == nil)
        #expect(InstallerKind.msiExitMeaning(0) == nil)
    }

    @Test
    func detectionReadsRealFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "msi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let msi = dir.appending(path: "game.msi")
        try oleHead.write(to: msi)
        #expect(InstallerKind.detect(msi) == .msiPackage)

        let exe = dir.appending(path: "setup.exe")
        try peHead().write(to: exe)
        #expect(InstallerKind.detect(exe) == .executable)

        // A path that doesn't exist must not crash, and must not divert a run.
        #expect(InstallerKind.detect(dir.appending(path: "nope.exe")) == .executable)
    }
}
