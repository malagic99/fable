import Foundation

enum SikarugirInstallError: LocalizedError {
    case homebrewMissing
    case stepFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .homebrewMissing:
            return "Homebrew isn't installed. Sikarugir is distributed as a Homebrew cask — install Homebrew from brew.sh first, then come back."
        case .stepFailed(let command, let output):
            let detail = output
                .split(separator: "\n")
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(String.init) ?? "no output"
            return "`\(command)` failed: \(detail)"
        }
    }
}

/// Installs Sikarugir on the user's behalf.
///
/// Sikarugir publishes no releases and no downloadable app — it exists only as
/// a Homebrew cask, behind a `brew trust` for its tap. Sending someone to the
/// project's GitHub page therefore lands them on an empty Releases tab, and
/// the real instructions are three terminal commands. That's a wall for
/// exactly the person Fable is trying to serve, so Fable runs them.
///
/// Deliberately not silent: the commands are surfaced before they run and
/// their output is streamed back, because this installs third-party software
/// system-wide and "it's doing something, trust me" is not good enough for
/// that.
enum SikarugirInstaller {

    /// Homebrew's two standard prefixes — Apple Silicon first, since Sikarugir
    /// only targets Apple Silicon anyway.
    private static let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static var homebrew: URL? {
        brewCandidates
            .map { URL(filePath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isHomebrewInstalled: Bool { homebrew != nil }

    /// The tap must be trusted before its cask will install, so this is two
    /// steps rather than one. Shown to the user verbatim.
    static let commands = [
        "brew trust Sikarugir-App/sikarugir",
        "brew install --cask Sikarugir-App/sikarugir/sikarugir",
    ]

    /// Runs the cask install, reporting each command as it starts.
    ///
    /// `brew trust` is tolerated failing: it errors when the tap is already
    /// trusted, which is the normal state on a second run and not a reason to
    /// stop. The install itself is not tolerated failing.
    static func install(progress: @MainActor (String) -> Void) async throws {
        guard let brew = homebrew else { throw SikarugirInstallError.homebrewMissing }

        for command in commands {
            await progress(command)
            let arguments = Array(command.split(separator: " ").dropFirst().map(String.init))
            let result = try await ProcessRunner.run(brew, arguments: arguments)
            guard result.succeeded || command.contains("trust") else {
                throw SikarugirInstallError.stepFailed(
                    command: command,
                    output: result.standardError.isEmpty ? result.standardOutput : result.standardError)
            }
        }
    }
}
