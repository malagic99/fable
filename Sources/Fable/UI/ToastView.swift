import SwiftUI

/// App-wide transient notifications (success/error/info), shown bottom
/// center and auto-dismissed.
@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable, Equatable {
        enum Style {
            case success, error, info
        }
        let id = UUID()
        let message: String
        let style: Style
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .info) {
        let toast = Toast(message: message, style: style)
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .error ? 6 : 3))
            guard !Task.isCancelled else { return }
            if self?.current == toast {
                self?.current = nil
            }
        }
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
}

struct ToastOverlay: ViewModifier {
    @EnvironmentObject private var toastCenter: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = toastCenter.current {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: toast.style))
                        .foregroundStyle(color(for: toast.style))
                    Text(toast.message)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.spring(duration: 0.3), value: toastCenter.current)
    }

    private func icon(for style: ToastCenter.Toast.Style) -> String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(for style: ToastCenter.Toast.Style) -> Color {
        switch style {
        case .success: .green
        case .error: .yellow
        case .info: .blue
        }
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
