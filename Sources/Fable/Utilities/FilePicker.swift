import AppKit
import UniformTypeIdentifiers

/// Thin wrapper around NSOpenPanel for choosing Windows executables.
@MainActor
enum FilePicker {
    /// Pick one Windows binary. `extensions` defaults to just `.exe`; the
    /// installer flows widen it to `.msi` as well, since a Windows Installer
    /// package is a perfectly ordinary way to ship a game.
    static func chooseExecutable(
        title: String,
        extensions: [String] = ["exe"],
        startingAt directory: URL? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        if let directory {
            panel.directoryURL = directory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// One image (for covers and backgrounds).
    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// One file by extension ("fableskin", "fablerecipe", …).
    static func chooseFile(extension ext: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A folder, with the confirm button named for the action.
    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A save destination with a suggested filename ("My Bottle.fbottle").
    static func chooseSaveDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// One or more .app bundles, starting in /Applications.
    static func chooseApplications() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
