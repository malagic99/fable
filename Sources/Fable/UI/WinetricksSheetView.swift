import SwiftUI

/// Browse-and-install sheet for the long tail of winetricks verbs.
/// Curated dependencies still live in DependenciesSection; this is the
/// "More from Winetricks" entry point for anything else.
struct WinetricksSheetView: View {
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var winetricksManager: WinetricksManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: WinetricksVerb.Category? = nil
    @State private var isPreparing = false
    @State private var prepError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if winetricksManager.isInstalled {
                browser
            } else {
                installPrompt
            }
            Divider()
            HStack {
                Text("Winetricks runs Windows installers inside the bottle. Some verbs need a network connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Winetricks")
                    .font(.title3.weight(.semibold))
                Text("\(bottle.installedWinetricksVerbs.count) installed in “\(bottle.name)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var installPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Winetricks isn't installed yet")
                .font(.headline)
            Text("It's a ~800 KB shell script with 500+ optional Windows runtimes and fonts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let prepError {
                Text(prepError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if isPreparing {
                ProgressView()
            } else {
                Button("Install Winetricks") { prepare() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var browser: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search verbs", text: $searchText, prompt: Text("dotnet, corefonts, dxvk…"))
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(WinetricksVerb.Category?.none)
                    ForEach(WinetricksVerb.Category.allCases) { category in
                        Text(category.displayName).tag(WinetricksVerb.Category?.some(category))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            .padding(16)

            List(filteredVerbs, id: \.id) { verb in
                row(for: verb)
            }
            .listStyle(.inset)
        }
    }

    private var filteredVerbs: [WinetricksVerb] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return winetricksManager.verbs.filter { verb in
            if let selectedCategory, verb.category != selectedCategory { return false }
            if query.isEmpty { return true }
            return verb.searchText.contains(query)
        }
    }

    @ViewBuilder
    private func row(for verb: WinetricksVerb) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verb.id)
                    .font(.callout.monospaced())
                Text(verb.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if winetricksManager.isInstalling(verb.id, in: bottle) {
                ProgressView().controlSize(.small)
            } else if bottle.installedWinetricksVerbs.contains(verb.id) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.iconOnly)
                    .help("Installed")
            } else {
                Button("Install") { install(verb) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Actions

    private func prepare() {
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                try await winetricksManager.ensureInstalled()
                prepError = nil
            } catch {
                prepError = error.localizedDescription
            }
        }
    }

    private func install(_ verb: WinetricksVerb) {
        Task {
            do {
                try await winetricksManager.install(
                    verb: verb,
                    in: bottle,
                    bottleManager: bottleManager,
                    wineManager: wineManager
                )
                toastCenter.success("Winetricks: \(verb.id) installed")
            } catch {
                toastCenter.error(error.localizedDescription)
            }
        }
    }
}
