import Foundation

/// A single line inside a Host block. Normal options are `keyword value`;
/// comments and blank lines are stored verbatim in `keyword` with `isRaw = true`
/// so nothing the user wrote is lost on save.
struct SSHOption: Identifiable, Equatable {
    var id = UUID()
    var keyword: String
    var value: String
    var isRaw: Bool = false
}

struct SSHHost: Identifiable, Equatable {
    var id = UUID()
    var patterns: String
    var options: [SSHOption]

    var displayName: String { patterns.isEmpty ? "(unnamed)" : patterns }

    func value(for keyword: String) -> String? {
        options.first {
            !$0.isRaw && $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame
        }?.value
    }

    var hostName: String { value(for: "HostName") ?? "" }
    var user: String { value(for: "User") ?? "" }
    var identityFile: String { value(for: "IdentityFile") ?? "" }
}
