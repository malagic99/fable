import Foundation
import SwiftUI

/// Localization helper for strings that don't go through SwiftUI's
/// `Text` (toasts, error descriptions, log messages). Looks up keys in
/// the package's Localizable.strings catalog.
///
/// SwiftUI's `Text("key")` and `LocalizedStringKey` resolve through
/// the same bundle automatically — those don't need this helper.
enum L10n {
    /// Look up a key with no arguments. Falls back to the key itself
    /// if no translation exists, matching SwiftUI's behavior so missing
    /// keys are visible during development.
    static func string(_ key: String, comment: StaticString = "") -> String {
        NSLocalizedString(key, bundle: .module, comment: String(describing: comment))
    }

    /// Look up a key with printf-style arguments. Translators can
    /// reorder %@ via positional specifiers (%1$@, %2$@).
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .module, comment: "")
        return String(format: format, arguments: arguments)
    }
}

extension LocalizedStringKey {
    /// Convenience for static analyzers that flag string literals.
    /// Just sugar — `LocalizedStringKey("foo")` would also work.
    static func l10n(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}
