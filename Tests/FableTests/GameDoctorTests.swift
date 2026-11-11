import Foundation
import Testing
@testable import Fable

/// Fable Doctor's log-signature matching.
@Suite struct GameDoctorTests {

    private func ids(_ findings: [CompatibilityFinding]) -> Set<String> {
        Set(findings.map(\.id))
    }

    // MARK: .NET Windows token (GOG Galaxy installer, 2026-11-03)

    /// Real lines from C:\ProgramData\GOG.com\Galaxy\logs\InstallerWebinstaller.log.
    private let galaxyLog = """
    [11/3/2026 2:35:25 AM] [information] Loading icon file: C:\\users\\x\\AppData\\Local\\Temp\\GalaxyInstaller_QrEic\\icon.ico
    [11/3/2026 2:35:25 AM] [error] Error: GetCurrentToken returned error 34374144
    [11/3/2026 2:35:25 AM] [information] Sending error to galaxy-client-reports.gog.com: Unexpected Error
    [11/3/2026 2:35:33 AM] [information] Exiting application with return code -1
    """

    /// Fable's own installer log for the same run: only Wine's chatter.
    private let fableInstallerLog = """
    wine: configuration in L"/x/prefix" has been updated.
    0150:err:kerberos:kerberos_LsaApInitializePackage no Kerberos support, expect problems
    """

    @Test
    func windowsTokenFailureIsABlockerThatPointsAtOfflineInstallers() throws {
        let finding = try #require(GameDoctor.diagnose(log: galaxyLog).first { $0.id == "doctor-dotnet-windows-token" })
        #expect(finding.severity == .knownBlocker)
        #expect(finding.suggestion.contains("offline installer"))
        // .NET apps that print the exception rather than a log line too.
        #expect(ids(GameDoctor.diagnose(log: "System.Security.Principal.WindowsIdentity.GetCurrent()"))
            .contains("doctor-dotnet-windows-token"))
        // Fable's log alone says nothing about it.
        #expect(!ids(GameDoctor.diagnose(log: fableInstallerLog)).contains("doctor-dotnet-windows-token"))
    }

    private func installerRun() throws -> (driveC: URL, fableLog: URL, galaxy: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "doctor-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        let driveC = root.appending(path: "drive_c", directoryHint: .isDirectory)
        let galaxy = driveC.appending(path: GameDoctor.installerOwnLogs[0])
        try FileManager.default.createDirectory(at: galaxy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(galaxyLog.utf8).write(to: galaxy)
        let fableLog = root.appending(path: "installer.log")
        try Data(fableInstallerLog.utf8).write(to: fableLog)
        return (driveC, fableLog, galaxy, root)
    }

    @Test
    func installerBlockerReadsTheInstallersOwnLogFromThisRun() throws {
        let run = try installerRun()
        defer { try? FileManager.default.removeItem(at: run.root) }
        let blocker = GameDoctor.installerBlocker(
            fableLog: run.fableLog, driveC: run.driveC, since: Date().addingTimeInterval(-60))
        #expect(blocker?.id == "doctor-dotnet-windows-token")
    }

    @Test
    func anInstallerLogFromAnEarlierAttemptIsIgnored() throws {
        let run = try installerRun()
        defer { try? FileManager.default.removeItem(at: run.root) }
        let earlier = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: earlier], ofItemAtPath: run.galaxy.path)
        #expect(GameDoctor.installerBlocker(
            fableLog: run.fableLog, driveC: run.driveC, since: Date().addingTimeInterval(-60)) == nil)
    }

    @Test
    func cleanLogYieldsNothing() {
        #expect(GameDoctor.diagnose(log: "fixme:everything is fine\ninfo:loaded ok").isEmpty)
    }

    @Test
    func missingVCRuntimeIsCaught() {
        let log = "err:module:import_dll Library MSVCP140.dll not found"
        let findings = GameDoctor.diagnose(log: log)
        // Two rules fire here (the specific vcredist one + the generic missing-dll).
        #expect(ids(findings).contains("doctor-vcredist"))
        #expect(findings.first(where: { $0.id == "doctor-vcredist" })?.severity == .caveat)
    }

    @Test
    func kernelAnticheatIsAHardBlocker() {
        let log = "Loading BEClient_x64.dll ... BattlEye service failed"
        let finding = GameDoctor.diagnose(log: log).first { $0.id == "doctor-anticheat" }
        #expect(finding?.severity == .knownBlocker)
    }

    @Test
    func easyAntiCheatMeansOnlineOnlyNotABlocker() {
        // Ace Combat 8: EAC runs in its offline mode on Wine, single-player works.
        let findings = GameDoctor.diagnose(log: "Loading EasyAntiCheat_x64.dll ... launching with null client")
        #expect(findings.first { $0.id == "doctor-anticheat-eac" }?.severity == .caveat)
        #expect(!findings.contains { $0.id == "doctor-anticheat" })
        // Alongside a kernel anti-cheat, only the blocker shows.
        let both = GameDoctor.diagnose(log: "easyanticheat ... vgc.exe")
        #expect(both.contains { $0.id == "doctor-anticheat" })
        #expect(!both.contains { $0.id == "doctor-anticheat-eac" })
    }

    @Test
    func matchingIsCaseInsensitive() {
        #expect(!GameDoctor.diagnose(log: "FAILED TO CREATE D3D12 DEVICE").isEmpty)
    }

    @Test
    func d3d12FailureSuggestsSikarugir() {
        let finding = GameDoctor.diagnose(log: "vkd3d: device removed").first { $0.id == "doctor-d3d12-device" }
        #expect(finding?.suggestion.contains("Sikarugir") == true)
    }

    // ——— The 2026-06 investigation signatures (docs/ARCHITECTURE.md) ———

    @Test
    func realLogLinesMatchTheInvestigationRules() {
        // Each pair: a line as it actually appears in the wild → the rule id.
        let cases: [(String, String)] = [
            ("Assertion failed: (GFXTHandle), Failed to dlopen D3DMetal", "doctor-d3dmetal-dlopen"),
            ("wine: could not load kernel32.dll, status c0000142", "doctor-abi-mismatch"),
            ("dlopen: library load disallowed by system policy", "doctor-quarantine"),
            ("Wine cannot find the FreeType font library.", "doctor-freetype"),
            ("err:secur32:schan_imp_init Failed to load libgnutls, secure connections will not be available.", "doctor-gnutls"),
            ("[service] Failed to create Service pipe (GLE 2)", "doctor-steamservice"),
            ("Execution of the command buffer was aborted due to an error during execution", "doctor-gpu-hang"),
            ("CreateTexture2D returned E_OUTOFMEMORY", "doctor-out-of-memory"),
            ("Denuvo Anti-Tamper: integrity check", "doctor-denuvo"),
            ("err:module:import_dll Library XAudio2_7.dll not found", "doctor-xaudio"),
            ("PhysXLoader.dll failed to initialize", "doctor-physx"),
            // The VotV/YeetPatch session, 2026-07-07 — both real lines:
            ("wine client error:0: version mismatch 856/942.\nYour wineserver binary was not upgraded correctly", "doctor-wineserver-mismatch"),
            ("Failed to resolve hostfxr.dll [not found]. Error code: 0x80008083", "doctor-dotnet-modern"),
            // Absolute Drift on DXMT, 2026-07-08:
            ("InitializeEngineGraphics failed", "doctor-unity-graphics-init"),
            // YeetPatch/VotV WPF on en-DK, 2026-07-09:
            ("System.Globalization.CultureNotFoundException: Culture is not supported. 4096 (0x1000) is an invalid culture identifier.", "doctor-wpf-culture-4096"),
            // BSG Tarkov launcher single-instance IPC on Wine Mono, 2026-07-09:
            ("System.Runtime.InteropServices.MarshalDirectiveException: Type CriticalHandle which is passed to unmanaged code must have a StructLayout attribute at IpcServerChannel.StartListening", "doctor-mono-ipc-singleinstance"),
            // .NET 8 single-file app: CoreCLR won't host on an older Wine, 2026-07:
            ("Failed to create CoreCLR, HRESULT: 0x8007046C", "doctor-coreclr-dotnet-host"),
            // Avalonia desktop app with no renderable surface under Wine, 2026-07:
            ("[WinUIComposition]Unable to initialize WinUI compositor: System.NotImplementedException", "doctor-avalonia-no-surface"),
        ]
        for (line, ruleID) in cases {
            #expect(ids(GameDoctor.diagnose(log: line)).contains(ruleID),
                    "expected \(ruleID) to match: \(line)")
        }
    }

    @Test
    func denuvoIsABlockerAndPointsAtStreaming() {
        let finding = GameDoctor.diagnose(log: "denuvo").first { $0.id == "doctor-denuvo" }
        #expect(finding?.severity == .knownBlocker)
        #expect(finding?.suggestion.contains("streaming") == true)
    }

    @Test
    func steamServiceFailurePointsAtTheCommitter() {
        let finding = GameDoctor.diagnose(log: "BOpenService failed (GLE 1060)")
            .first { $0.id == "doctor-steamservice" }
        #expect(finding?.suggestion.contains("Finish Stuck Steam Downloads") == true)
    }

    // ——— Cross-backend crash correlation (the First Light rule) ———

    @Test
    func crashSignatureClassifiesOnlyTheBreakpointFamily() {
        #expect(GameDoctor.crashSignature(exitCode: 1, logTail: "Unhandled exception: 0x80000003") == "int3")
        #expect(GameDoctor.crashSignature(exitCode: 5, logTail: "wine: int3 in 64-bit code") == "int3")
        #expect(GameDoctor.crashSignature(exitCode: 5, logTail: "EXCEPTION_BREAKPOINT at 0xcb9dd8") == "int3")
        // Ordinary failures don't correlate — they're config, not protector.
        #expect(GameDoctor.crashSignature(exitCode: 1, logTail: "err:module:import_dll Library FOO.dll") == nil)
        #expect(GameDoctor.crashSignature(exitCode: 3, logTail: "") == nil)
    }

    @Test
    func crossBackendFindingIsABlockerThatNamesTheBackends() {
        let finding = GameDoctor.crossBackendFinding(signature: "int3", backends: ["GPTK", "Sikarugir"])
        #expect(finding.severity == .knownBlocker)
        #expect(finding.detail.contains("GPTK and Sikarugir"))
        #expect(finding.suggestion.contains("Stop switching backends"))
    }

    // ——— Naming the culprit DLL ———

    @Test
    func missingDLLIsNamedInTheFinding() {
        let log = """
        err:module:import_dll Library XAPOFX1_5.dll (which is needed by L"C:\\\\game\\\\game.exe") not found
        err:module:import_dll Library D3DX9_43.dll (which is needed by L"C:\\\\game\\\\game.exe") not found
        err:module:import_dll Library xapofx1_5.dll (which is needed by L"C:\\\\game\\\\other.exe") not found
        """
        #expect(GameDoctor.missingDLLs(in: log) == ["XAPOFX1_5.dll", "D3DX9_43.dll"])

        let finding = GameDoctor.diagnose(log: log).first { $0.id == "doctor-missing-dll" }
        #expect(finding?.detail.contains("XAPOFX1_5.dll, D3DX9_43.dll") == true)
    }

    @Test
    func d3d12AdapterFailureIsDiagnosed() {
        let log = """
        LogRHI: Error: Dynamic RHI module `D3D12RHI` for chosen RHI / feature \
        level `DirectX 12 (SM6)` is not supported, or failed to choose a valid \
        graphics adapter
        """
        let finding = GameDoctor.diagnose(log: log).first { $0.id == "doctor-d3d12-rhi-unsupported" }
        #expect(finding?.severity == .caveat)
        #expect(finding?.suggestion.contains("Sikarugir") == true)
    }

    /// Wine probes the Vulkan ICD on every launch, so a MoltenVK banner is
    /// present even when D3DMetal is working. A healthy log must stay silent —
    /// the old banner-keyed rule told Sikarugir users to switch to Sikarugir.
    @Test
    func moltenVKBannerAloneIsNotADiagnosis() {
        let log = """
        [mvk-info] MoltenVK version 1.4.1, supporting Vulkan version 1.4.334.
        [mvk-info] GPU device:
            model: Apple M4 Pro
        [mvk-info] Created VkInstance for Vulkan version 1.0.334
        LogInit: Display: Game Engine Initialized.
        """
        #expect(GameDoctor.diagnose(log: log).isEmpty)
    }

    @Test
    func vetoSuppressesARuleWhenContraryEvidenceIsPresent() {
        let rule = GameDoctor.Rule(
            id: "t", needles: ["boom"], vetoes: ["actually fine"],
            severity: .caveat, title: "t", detail: "d", suggestion: "s")
        #expect(rule.vetoes == ["actually fine"])
    }

    @Test
    func rulesHaveUniqueIDsAndNonEmptyGuidance() {
        // The database is data — lock its invariants so a bulk edit can't
        // ship a duplicate id or an empty suggestion.
        let ids = GameDoctor.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for rule in GameDoctor.rules {
            #expect(!rule.needles.isEmpty)
            #expect(!rule.suggestion.isEmpty)
            // Needles must be lowercase — matching lowercases the haystack only.
            for needle in rule.needles {
                #expect(needle == needle.lowercased(), "needle not lowercase: \(needle)")
            }
        }
    }

    @Test
    func diagnosesFromAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "run.log")
        try "wine: mscoree not found".write(to: url, atomically: true, encoding: .utf8)
        #expect(GameDoctor.diagnose(logFile: url).contains { $0.id == "doctor-dotnet" })
        // Missing file → empty, never throws.
        #expect(GameDoctor.diagnose(logFile: dir.appending(path: "nope.log")).isEmpty)
    }
}
