import AppKit
import UniformTypeIdentifiers

/// Thin wrapper around NSOpenPanel for choosing Windows executables.
@MainActor
enum FilePicker {
    static func chooseExecutable(title: String, startingAt directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let exeType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exeType]
        }
        if let directory {
            panel.directoryURL = directory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
