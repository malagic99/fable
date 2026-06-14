import SwiftUI

/// Detail page for a single bottle: info, game list, rename/delete actions.
struct BottleDetailView: View {
    let bottleID: Bottle.ID

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var dxmtManager: DXMTManager
    @EnvironmentObject private var gptkManager: GPTKManager
    @EnvironmentObject private var crossOverManager: CrossOverManager
    @EnvironmentObject private var sikarugirManager: SikarugirManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var diskUsageStore: BottleDiskUsageStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingRename = false
    @State private var renameText = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var installerExe: URL?
    @State private var importExe: URL?
    @State private var gogInstallerExe: URL?
    @State private var isRepairing = false

    var body: some View {
        if let bottle = bottleManager.bottle(with: bottleID) {
            detailContent(for: bottle)
                .onAppear {
                    bottleManager.reconcileWindowsVersion(for: bottleID)
                    diskUsageStore.scan(bottle, manager: bottleManager)
                }
        } else {
            // Deleted while visible (or stale link) — nothing to show.
            ContentUnavailableView("Bottle Not Found", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func detailContent(for bottle: Bottle) -> some View {
        Form {
            Section("Bottle") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Windows Version", value: bottle.windowsVersion.displayName)
                LabeledContent("Status") {
                    switch bottle.status {
                    case .ready:
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .provisioning:
                        Label("Setting up", systemImage: "clock")
                            .foregroundStyle(.orange)
                    case .broken:
                        HStack {
                            Label("Setup was interrupted", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            if isRepairing {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Repair") { repair(bottle) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                LabeledContent("Created") {
                    Text(bottle.createdAt, format: .dateTime.day().month().year())
                }
                LabeledContent("Location") {
                    HStack {
                        Text(bottleManager.directory(for: bottle).path)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [bottleManager.directory(for: bottle)]
                            )
                        }
                        .controlSize(.small)
                    }
                }
                LabeledContent("Wine Tools") {
                    HStack {
                        Button("Wine Settings…") { openTool("winecfg") }
                            .controlSize(.small)
                            .help("Audio, graphics, drive mappings, Windows version (winecfg)")
                        Button("Registry Editor…") { openTool("regedit") }
                            .controlSize(.small)
                            .help("Edit this bottle's Windows registry (regedit)")
                    }
                }
                .disabled(bottle.status != .ready)
            }

            Section {
                if bottle.games.isEmpty {
                    Text("No games yet. Run a Windows installer, or add a game's .exe directly.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bottle.games) { game in
                        VStack(alignment: .leading, spacing: 6) {
                            GameLauncherView(game: game, bottle: bottle)
                            CompatibilityBanner(game: game, bottle: bottle)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Games")
                    Spacer()
                    Button("Run Installer…") { pickInstaller(for: bottle) }
                        .controlSize(.small)
                        .disabled(bottle.status != .ready)
                        .help("Run a Windows setup.exe inside this bottle")
                    Button("Add Game…") { pickGame(for: bottle) }
                        .controlSize(.small)
                        .disabled(bottle.status != .ready)
                        .help("Add a game's .exe to this bottle")
                }
            }

            Section {
                Picker("Backend", selection: Binding(
                    get: { bottle.graphicsBackend },
                    set: { setGraphicsBackend($0, bottle: bottle) }
                )) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .disabled(bottle.status != .ready)
            } header: {
                Text("Graphics")
            } footer: {
                Text(graphicsFooter(for: bottle.graphicsBackend))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Metal Performance HUD", isOn: Binding(
                    get: { bottle.performance.metalHUD },
                    set: { setMetalHUD($0, bottle: bottle) }
                ))
                .help("Apple's built-in FPS / frametime / GPU overlay (MTL_HUD_ENABLED)")

                Picker("Frame Rate Cap", selection: Binding(
                    get: { bottle.performance.frameRateCap ?? 0 },
                    set: { setFrameRateCap($0 == 0 ? nil : $0, bottle: bottle) }
                )) {
                    Text("Uncapped").tag(0)
                    Text("120 fps").tag(120)
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }
                .disabled(bottle.graphicsBackend == .off)

                if bottle.graphicsBackend == .gptk {
                    Toggle("MetalFX Upscaling", isOn: Binding(
                        get: { bottle.performance.metalFXUpscaling },
                        set: { setMetalFXUpscaling($0, bottle: bottle) }
                    ))
                    .help("D3DMetal 4 neural upscaler — render lower, upscale via Metal")
                }
            } header: {
                Text("Performance")
            } footer: {
                Text(performanceFooter(for: bottle.graphicsBackend))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DependenciesSection(bottle: bottle)

            Section {
                HStack {
                    LabeledContent("Prefix size") {
                        if diskUsageStore.isScanning(bottle.id) {
                            ProgressView().controlSize(.small)
                        } else if let bytes = diskUsageStore.size(for: bottle.id) {
                            Text(BottleDiskUsage.formatted(bytes))
                                .monospacedDigit()
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Recompute") {
                        diskUsageStore.scan(bottle, manager: bottleManager)
                    }
                    .controlSize(.small)
                    .disabled(diskUsageStore.isScanning(bottle.id))
                }
                Button("Clean Wine Temp Files…") { cleanTempFiles(in: bottle) }
                    .disabled(bottle.status != .ready || isAnyGameRunning(in: bottle))
            } header: {
                Text("Storage")
            } footer: {
                Text("Cleans drive_c/windows/Temp and each user's Temp folder. Wine recreates these on demand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Force Kill Wine Processes…", role: .destructive) {
                    forceKill(bottle)
                }
                .disabled(bottle.status != .ready)
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Runs wineserver -k against this bottle's prefix — the escape hatch when a hung game ignores Stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    renameText = bottle.name
                    isShowingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .help("Rename this bottle")

                Button {
                    duplicate(bottle)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(bottle.status != .ready || isAnyGameRunning(in: bottle))
                .help(isAnyGameRunning(in: bottle)
                      ? "Stop running games before duplicating"
                      : "Clone this bottle and its installed games")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this bottle")
            }
        }
        .alert("Rename Bottle", isPresented: $isShowingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                do {
                    try bottleManager.renameBottle(bottle.id, to: renameText)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $installerExe) { exe in
            GameInstallerView(bottle: bottle, installerExe: exe)
        }
        .sheet(item: $importExe) { exe in
            ImportGameView(bottle: bottle, executable: exe)
        }
        .sheet(item: $gogInstallerExe) { exe in
            GOGInstallView(bottle: bottle, installer: exe) { installer in
                installerExe = installer
            }
        }
        .confirmationDialog(
            "Delete “\(bottle.name)”?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete Bottle", role: .destructive) {
                do {
                    try bottleManager.deleteBottle(bottle.id)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This permanently removes the bottle and everything installed in it.")
        }
    }

    // MARK: Troubleshooting

    private func forceKill(_ bottle: Bottle) {
        Task {
            do {
                try await wineManager.forceKillPrefix(
                    bottleManager.prefixDirectory(for: bottle)
                )
                toastCenter.success(L10n.string("toast.bottle.killed", bottle.name))
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Storage

    private func cleanTempFiles(in bottle: Bottle) {
        Task {
            do {
                let freed = try await diskUsageStore.cleanTempFiles(
                    in: bottle, manager: bottleManager
                )
                toastCenter.success(L10n.string("toast.disk.freed", BottleDiskUsage.formatted(freed)))
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Duplicate

    private func isAnyGameRunning(in bottle: Bottle) -> Bool {
        bottle.games.contains { gameLauncher.isRunning($0.id) }
    }

    private func duplicate(_ bottle: Bottle) {
        // Find a non-clashing "<name> Copy"/"Copy 2"/… name.
        let base = "\(bottle.name) Copy"
        var candidate = base
        var counter = 2
        while bottleManager.bottles.contains(where: {
            $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        do {
            let clone = try bottleManager.cloneBottle(bottle.id, newName: candidate)
            toastCenter.success(L10n.string("toast.bottle.duplicated", clone.name))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Repair

    private func repair(_ bottle: Bottle) {
        isRepairing = true
        Task {
            defer { isRepairing = false }
            do {
                try await wineManager.ensureWineInstalled()
                // wineboot completes/repairs a partial prefix in place.
                try await wineManager.createPrefix(
                    at: bottleManager.prefixDirectory(for: bottle),
                    windowsVersion: bottle.windowsVersion
                )
                try bottleManager.setStatus(.ready, for: bottle.id)
                toastCenter.success("“\(bottle.name)” repaired")
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Wine tools

    private func openTool(_ tool: String) {
        guard let bottle = bottleManager.bottle(with: bottleID) else { return }
        do {
            try wineManager.openTool(tool, inPrefix: bottleManager.prefixDirectory(for: bottle))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Graphics

    private func graphicsFooter(for backend: GraphicsBackend) -> String {
        switch backend {
        case .off:
            "Best for D3D9-era games. DirectX renders through Wine's built-in path."
        case .dxmt:
            "Best for DirectX 11/10 games. D3D12-only games need Game Porting Toolkit or DXVK."
        case .gptk:
            "Runs games on Apple's Game Porting Toolkit Wine with D3DMetal (D3D9–12). Downloads ~240 MB on first use. Wine 7.7 base — fails on modern UE5 SEH unwinding."
        case .dxvk:
            "D3D11/12 → Vulkan → MoltenVK → Metal, on modern Wine (11.10). Best for 2024+ UE5 games that crash on GPTK. ~20-30% slower than D3DMetal but supports modern Wine SEH. Needs `winetricks dxvk` in the bottle."
        case .crossover:
            "Routes through your installed CrossOver. Modern wine 9+ AND Apple-licensed D3DMetal — the highest-compatibility path. Requires CrossOver (codeweavers.com)."
        case .sikarugir:
            "Sikarugir's wine-10.0 + D3DMetal recompiled against it. The free matched pair — modern SEH AND real D3D12→Metal. Best for 2024+ D3D12 games. Requires Sikarugir installed."
        }
    }

    private func setGraphicsBackend(_ backend: GraphicsBackend, bottle: Bottle) {
        Task {
            do {
                switch backend {
                case .dxmt:
                    try await dxmtManager.ensureInstalled()
                    try dxmtManager.enable(
                        in: bottle,
                        bottleManager: bottleManager,
                        wineManager: wineManager
                    )
                case .gptk:
                    try await gptkManager.ensureInstalled()
                case .dxvk:
                    // DXVK is installed via the existing Winetricks UI:
                    // bottle's Dependencies → "More from Winetricks…" → dxvk.
                    // Just persist the backend choice here.
                    break
                case .crossover:
                    // CrossOver is auto-detected; nothing to install on our side.
                    crossOverManager.refresh()
                case .sikarugir:
                    // Extracts Sikarugir's wine-10.0 engine + overlays its
                    // d3dmetal renderer into Fable's components (one-time).
                    try await sikarugirManager.ensureInstalled()
                case .off:
                    // Launches route around any installed DLLs.
                    break
                }
                try bottleManager.setGraphics(backend: backend, for: bottle.id)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performanceFooter(for backend: GraphicsBackend) -> String {
        switch backend {
        case .off:
            "Frame-rate cap and MetalFX upscaling need a translation backend (DXMT, DXVK, or GPTK)."
        case .dxmt:
            "Frame-rate cap is applied through DXMT. MetalFX upscaling needs the GPTK backend."
        case .gptk:
            "All performance toggles are active. MetalFX is a D3DMetal 4 feature."
        case .dxvk:
            "Frame-rate cap routed through DXVK_FRAME_RATE. MetalFX is GPTK-only."
        case .crossover:
            "CrossOver manages its own performance config — Metal HUD still works via MTL_HUD_ENABLED."
        case .sikarugir:
            "Metal HUD + MetalFX work through D3DMetal. Frame-rate cap isn't wired for this backend yet."
        }
    }

    private func setFrameRateCap(_ cap: Int?, bottle: Bottle) {
        var perf = bottle.performance
        perf.frameRateCap = cap
        try? bottleManager.setPerformance(perf, for: bottle.id)
    }

    private func setMetalHUD(_ enabled: Bool, bottle: Bottle) {
        var perf = bottle.performance
        perf.metalHUD = enabled
        try? bottleManager.setPerformance(perf, for: bottle.id)
    }

    private func setMetalFXUpscaling(_ enabled: Bool, bottle: Bottle) {
        var perf = bottle.performance
        perf.metalFXUpscaling = enabled
        try? bottleManager.setPerformance(perf, for: bottle.id)
    }

    // MARK: Game actions

    private func pickInstaller(for bottle: Bottle) {
        guard let exe = FilePicker.chooseExecutable(title: "Choose a Windows installer (.exe)") else {
            return
        }
        // GOG/Inno Setup installers get the direct-extraction offer; old
        // ones crash Wine's WoW64. Detection needs innoextract installed.
        Task {
            if await InnoExtractor.isInnoSetup(exe) {
                gogInstallerExe = exe
            } else {
                installerExe = exe
            }
        }
    }

    private func pickGame(for bottle: Bottle) {
        guard let exe = FilePicker.chooseExecutable(title: "Choose a game executable (.exe)") else {
            return
        }
        // Already inside the bottle: register directly. Outside: offer to
        // copy it in.
        let driveC = bottleManager.driveCDirectory(for: bottle)
        if GameInstaller.pathInDriveC(of: exe, driveC: driveC) != nil {
            do {
                try GameInstaller().registerGame(executable: exe, bottle: bottle, bottleManager: bottleManager)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            importExe = exe
        }
    }
}

// Lets URL drive `.sheet(item:)` for the installer/import flows.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
