import SwiftUI

/// In-app log viewer: monospaced, auto-refreshing while the file grows,
/// with an errors-only filter. Finder reveal stays as the escape hatch.
struct LogViewerView: View {
    let logURL: URL

    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var errorsOnly = false

    private var displayedLines: [String] {
        let lines = content.components(separatedBy: "\n")
        guard errorsOnly else { return lines }
        return lines.filter {
            $0.localizedCaseInsensitiveContains("err:")
                || $0.localizedCaseInsensitiveContains("error")
                || $0.localizedCaseInsensitiveContains("warn:")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(logURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Toggle("Errors only", isOn: $errorsOnly)
                    .toggleStyle(.checkbox)
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.caption.monospaced())
                                .foregroundStyle(lineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .background(.black.opacity(0.04))
                .onChange(of: displayedLines.count) {
                    proxy.scrollTo(displayedLines.count - 1, anchor: .bottom)
                }
            }

            Divider()

            SheetActionBar {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
            } trailing: {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 640, height: 420)
        .task {
            // Refresh while open; cheap for the file sizes Wine produces.
            while !Task.isCancelled {
                content = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(log file unavailable)"
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("err:") { return .red }
        if line.contains("warn:") { return .orange }
        return .primary
    }
}
