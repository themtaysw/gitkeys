import SwiftUI
import AppKit

func copyToClipboard(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}

/// Replaces the user's home directory prefix with `~` for tidy config values.
func tildeify(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// A read-only, selectable, monospaced text box for showing keys and command output.
struct MonospacedBox: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? " " : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }
}
