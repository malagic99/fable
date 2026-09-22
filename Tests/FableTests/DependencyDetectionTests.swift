import Foundation
import Testing

@testable import Fable

@Suite("Dependency detection")
struct DependencyDetectionTests {
    private let key = #"Software\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64"#

    @Test
    func readsInstalledFlagFromItsOwnSection() {
        let registry = """
        [Software\\\\Microsoft\\\\VisualStudio\\\\14.0\\\\VC\\\\Runtimes\\\\x64] 1790022966
        "Bld"=dword:0000898b
        "Installed"=dword:00000001
        "Major"=dword:0000000e
        """
        #expect(DependencyInstaller.registryReportsInstalled(key, in: registry))
    }

    /// Microsoft's redistributable writes `…\Runtimes\X64`; winetricks' verbs
    /// write `…\x64`. Both are the same key to Windows, and both turn up on
    /// real bottles, so an exact match would miss half of them.
    @Test
    func keyMatchIsCaseInsensitive() {
        let registry = """
        [Software\\\\Microsoft\\\\VisualStudio\\\\14.0\\\\VC\\\\Runtimes\\\\X64] 1790089778
        "Installed"=dword:00000001
        """
        #expect(DependencyInstaller.registryReportsInstalled(key, in: registry))
    }

    @Test
    func absentKeyMeansNotInstalled() {
        #expect(!DependencyInstaller.registryReportsInstalled(key, in: "[Software\\\\Other]\n"))
    }

    @Test
    func zeroedInstalledFlagMeansNotInstalled() {
        let registry = """
        [Software\\\\Microsoft\\\\VisualStudio\\\\14.0\\\\VC\\\\Runtimes\\\\x64] 1
        "Installed"=dword:00000000
        """
        #expect(!DependencyInstaller.registryReportsInstalled(key, in: registry))
    }

    /// Wine's `Installer\UserData` breadcrumbs quote the same registry path as
    /// a plain string value, so a substring search over the file would report a
    /// runtime that was never installed.
    @Test
    func pathMentionedInAnotherSectionDoesNotCount() {
        let registry = """
        [Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Installer\\\\UserData\\\\S-1-5-18\\\\Components\\\\ABC] 1
        "18F2FE5BB35CB6548BDCE9E3ACB2C9AA"="02:\\\\SOFTWARE\\\\Microsoft\\\\VisualStudio\\\\14.0\\\\VC\\\\Runtimes\\\\X64\\\\Version"
        "Installed"=dword:00000001
        """
        #expect(!DependencyInstaller.registryReportsInstalled(key, in: registry))
    }

    /// The bug this replaced: Wine ships its own builtin `msvcp140.dll`, so a
    /// file check reported the Visual C++ runtime present on every prefix from
    /// creation — and Fable skipped the install on bottles that never had it.
    @Test
    func visualCPlusPlusDependenciesDoNotDetectByFile() {
        let vcredists = DependencyCatalog.all.filter { $0.kind == .vcRedist }
        #expect(!vcredists.isEmpty)
        for dependency in vcredists {
            #expect(dependency.detectionRegistryKey != nil)
        }
    }
}
