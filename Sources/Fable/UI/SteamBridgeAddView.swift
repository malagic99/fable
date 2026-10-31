import AppKit
import SwiftUI

/// Adds a Steam game that plays through the native Steam bridge: its Windows
/// build runs in a Sikarugir bottle and talks to the Mac Steam app. Look the
/// game up (anonymously), download its Windows build in Terminal (you sign in
/// to steamcmd there; Fable never sees your password), then it's on the wall.
struct SteamBridgeAddView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var bridge: SteamBridge.Status = SteamBridge.status()
    @State private var input = ""
    @State private var info: SteamAppInfo?
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var targetBottle: Bottle.ID?
    @State private var marker: URL?

    private var readyBottles: [Bottle] {
        bottleManager.bottles.filter { $0.status == .ready }
    }

    private var bridgeReady: Bool {
        if case .ready = bridge { return true }
        return false
    }

    private var isDownloaded: Bool {
        guard let info, let exe = info.windowsExecutable,
              let bottle = readyBottles.first(where: { $0.id == targetBottle }) else { return false }
        let path = "\(SteamCmd.installFolder(appID: info.appID))/\(exe)"
        return FileManager.default.fileExists(atPath: bottleManager.driveCDirectory(for: bottle).appending(path: path).path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a Steam game (native bridge)").font(.headline)
                Text("Plays the game's Windows build through your Mac Steam app — no Steam inside Wine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                bridgeSection
                lookupSection
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 500, height: 420)
        .onAppear { targetBottle = targetBottle ?? preferredBottle() }
        .task(id: marker) { await waitForDownload() }
    }

    // MARK: Sections

    @ViewBuilder
    private var bridgeSection: some View {
        switch bridge {
        case .ready:
            Label("Bridge ready", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        case .notBuilt, .damaged:
            VStack(alignment: .leading, spacing: 8) {
                Label("The bridge isn't built on this Mac yet", systemImage: "hammer")
                    .font(.callout)
                Text("It's built from Valve's source on your Mac — a few minutes, once. You need Homebrew's mingw-w64, bison and autoconf.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if SteamBridge.bundledBuildScript != nil {
                        Button("Build in Terminal…") { buildBridge() }
                    } else {
                        Text(verbatim: "scripts/steam-bridge/build.sh")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Button("Check Again") { bridge = SteamBridge.status() }
                }
            }
        }
    }

    private var lookupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Steam app ID or store link", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { lookUp() }
                Button("Look Up") { lookUp() }
                    .disabled(SteamAppInfo.appID(fromInput: input) == nil || isLookingUp)
            }
            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Asking Steam… the first time also sets up steamcmd.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let info {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.name).font(.body.weight(.semibold))
                    Text(verbatim: info.windowsExecutable ?? "")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if readyBottles.isEmpty {
                Label("Create a bottle first", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Into", selection: $targetBottle) {
                    ForEach(readyBottles) { bottle in
                        Text(bottle.name).tag(Optional(bottle.id))
                    }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if marker != nil {
                ProgressView().controlSize(.small)
                Text("Waiting for Terminal…").font(.caption).foregroundStyle(.secondary)
            } else if isDownloaded {
                Button("Add to Bottle") { register() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Download in Terminal…") { download() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(info == nil || targetBottle == nil || !bridgeReady)
            }
        }
        .padding(16)
    }

    // MARK: Actions

    /// A Sikarugir bottle if there is one — bridge games run on Sikarugir.
    private func preferredBottle() -> Bottle.ID? {
        (readyBottles.first { $0.graphicsBackend == .sikarugir } ?? readyBottles.first)?.id
    }

    private func lookUp() {
        guard let appID = SteamAppInfo.appID(fromInput: input) else { return }
        isLookingUp = true
        errorMessage = nil
        info = nil
        Task {
            do {
                info = try await SteamCmd.appInfo(appID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func buildBridge() {
        guard let script = SteamBridge.bundledBuildScript else { return }
        do {
            try openInTerminal(SteamBridge.buildCommand(script: script), name: "build-steam-bridge")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download() {
        guard let info, let bottle = readyBottles.first(where: { $0.id == targetBottle }) else { return }
        let installDir = bottleManager.driveCDirectory(for: bottle)
            .appending(path: SteamCmd.installFolder(appID: info.appID), directoryHint: .isDirectory)
        let done = AppPaths.downloads.appending(path: "steam-bridge-\(info.appID).done")
        errorMessage = nil
        do {
            try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: done)
            try openInTerminal(
                SteamCmd.downloadCommand(info: info, installDir: installDir, marker: done),
                name: "steam-bridge-\(info.appID)"
            )
            marker = done
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Polls the marker the Terminal script writes when steamcmd finishes.
    private func waitForDownload() async {
        guard let marker else { return }
        while !Task.isCancelled {
            if let text = try? String(contentsOf: marker, encoding: .utf8) {
                self.marker = nil
                if text.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
                    register()
                } else {
                    errorMessage = L10n.string("steambridge.download_failed")
                }
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func register() {
        guard let info, let target = targetBottle else { return }
        do {
            let game = try bottleManager.addSteamBridgeGame(info, to: target)
            toastCenter.success(L10n.string("steambridge.added", game.name))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes an executable `.command` script and opens it, which runs it in
    /// Terminal where the user can type into it.
    private func openInTerminal(_ script: String, name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: AppPaths.downloads, withIntermediateDirectories: true)
        let file = AppPaths.downloads.appending(path: "\(name).command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }
}
