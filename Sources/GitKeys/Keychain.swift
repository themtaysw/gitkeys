import Foundation
import Security

/// Minimal Keychain wrapper for Git-host API tokens.
///
/// Tokens are stored as generic-password items under a single service name,
/// with the normalized Git host name as the account. A token only ever leaves
/// the Keychain to be placed in an `Authorization` / `PRIVATE-TOKEN` header
/// over HTTPS — it is never logged, printed, or persisted anywhere else.
enum TokenStore {
    private static let service = "com.matej.gitkeys.token"

    /// Normalizes a host for use as the Keychain account — the same cleaning
    /// the upload path applies — so "https://GitLab.example.com/" and
    /// "gitlab.example.com" share a single item. Without this, saving under
    /// one spelling and deleting under another would silently leave the token
    /// behind, and prefill would miss it.
    private static func normalize(_ host: String) -> String {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("https://") { name = String(name.dropFirst("https://".count)) }
        if name.hasPrefix("http://") { name = String(name.dropFirst("http://".count)) }
        if let slash = name.firstIndex(of: "/") { name = String(name[..<slash]) }
        return name
    }

    /// Attributes identifying the item for a given account string.
    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Saves (or replaces) the token stored for `host`.
    static func save(host: String, token: String) {
        let account = normalize(host)
        guard !account.isEmpty, let data = token.data(using: .utf8) else { return }

        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "GitKeys token for \(account)"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Returns the token stored for `host`, or nil when none exists. Falls
    /// back to the raw spelling for items saved before hosts were normalized.
    static func load(host: String) -> String? {
        let account = normalize(host)
        guard !account.isEmpty else { return nil }
        if let token = loadItem(account: account) { return token }

        // Legacy item stored under the exact spelling (e.g. with "https://").
        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw != account, !raw.isEmpty {
            return loadItem(account: raw)
        }
        return nil
    }

    private static func loadItem(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the token stored for `host`, if any — including a legacy item
    /// saved under the exact spelling before hosts were normalized.
    static func delete(host: String) {
        let account = normalize(host)
        guard !account.isEmpty else { return }
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw != account, !raw.isEmpty {
            SecItemDelete(baseQuery(account: raw) as CFDictionary)
        }
    }
}
