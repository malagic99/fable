import Foundation
import Testing
@testable import Fable

/// The keyboard-layout self-heal — repairs Wine's invalid 0x1000 placeholder
/// that crashes WPF apps (CultureNotFoundException 4096) on non-US-locale
/// Macs. Found diagnosing Voices of the Void / YeetPatch on an en-DK Mac.
@MainActor
@Suite struct KeyboardLayoutReconcileTests {
    private let fm = FileManager.default

    private func makeManager() -> WineManager {
        WineManager(componentManager: ComponentManager(), catalog: VersionCatalog(components: [:]))
    }

    /// A user.reg with the broken Preload, as Wine writes it on an en-DK host.
    private let brokenReg = """
    WINE REGISTRY Version 2

    [Keyboard Layout\\\\Preload] 1783612283
    #time=1dd0fbacad2b4be
    "1"="00001000"

    [Software\\\\Wine] 123
    "Something"="else"
    """

    @Test
    func repairsOnlyTheInvalidPlaceholder() {
        let fixed = try? #require(WineManager.keyboardLayoutRepaired(brokenReg))
        #expect(fixed?.contains(#""1"="00000409""#) == true)
        #expect(fixed?.contains("00001000") == false)
        // Everything else is untouched.
        #expect(fixed?.contains(#""Something"="else""#) == true)
    }

    @Test
    func leavesAValidLayoutAlone() {
        // A prefix with a real US layout already → nil (nothing to do).
        let goodReg = brokenReg.replacingOccurrences(of: "00001000", with: "00000409")
        #expect(WineManager.keyboardLayoutRepaired(goodReg) == nil)
        // A Danish layout (0x0406) is valid too — never rewritten.
        let danishReg = brokenReg.replacingOccurrences(of: "00001000", with: "00000406")
        #expect(WineManager.keyboardLayoutRepaired(danishReg) == nil)
    }

    @Test
    func reconcileRewritesTheFileOnDisk() throws {
        let prefix = fm.temporaryDirectory.appending(path: "kbd-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: prefix) }
        let userReg = prefix.appending(path: "user.reg")
        try brokenReg.write(to: userReg, atomically: true, encoding: .utf8)

        makeManager().reconcileKeyboardLayout(at: prefix)

        let after = try String(contentsOf: userReg, encoding: .utf8)
        #expect(after.contains(#""1"="00000409""#))
        #expect(!after.contains("00001000"))

        // Second run is a clean no-op (idempotent) and never throws when the
        // file is absent.
        makeManager().reconcileKeyboardLayout(at: prefix)
        #expect(try String(contentsOf: userReg, encoding: .utf8) == after)
        makeManager().reconcileKeyboardLayout(at: prefix.appending(path: "nope"))
    }
}
