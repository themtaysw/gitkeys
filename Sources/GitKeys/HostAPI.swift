import Foundation

/// Which kind of Git host we are talking to. Self-hosted GitLab is the
/// primary audience, so anything that is not github.com is treated as GitLab.
enum HostKind {
    case github
    case gitlab

    static func detect(from host: String) -> HostKind {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("https://") { name = String(name.dropFirst("https://".count)) }
        if name.hasPrefix("http://") { name = String(name.dropFirst("http://".count)) }
        if let slash = name.firstIndex(of: "/") { name = String(name[..<slash]) }
        if name.hasPrefix("www.") { name = String(name.dropFirst("www.".count)) }
        return name == "github.com" ? .github : .gitlab
    }
}

/// Uploads SSH public keys to a Git host's REST API.
///
/// Security notes: requests are HTTPS-only (plain http hosts are rejected),
/// the token travels only in the `PRIVATE-TOKEN` / `Authorization` header,
/// and no returned message ever contains the token.
struct HostAPIClient {

    /// Default key title: "GitKeys — <computer name>", plus the public key's
    /// comment when one is present.
    static func defaultTitle(keyComment: String) -> String {
        let machine = Host.current().localizedName ?? "Mac"
        var title = "GitKeys — \(machine)"
        let comment = keyComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            title += " (\(comment))"
        }
        return title
    }

    /// POSTs `publicKey` to the host's user-keys endpoint. Returns a
    /// human-readable outcome; never throws and never leaks the token.
    static func uploadKey(host: String, token: String, title: String,
                          publicKey: String) async -> (ok: Bool, message: String) {
        let rawHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawHost.lowercased().hasPrefix("http://") {
            return (false, "Refusing to send a token over plain HTTP — use an HTTPS host.")
        }

        var cleanHost = rawHost
        if cleanHost.lowercased().hasPrefix("https://") {
            cleanHost = String(cleanHost.dropFirst("https://".count))
        }
        while cleanHost.hasSuffix("/") { cleanHost = String(cleanHost.dropLast()) }
        guard !cleanHost.isEmpty else {
            return (false, "Enter a host name first.")
        }

        let kind = HostKind.detect(from: cleanHost)
        let endpoint: String
        switch kind {
        case .github: endpoint = "https://api.github.com/user/keys"
        case .gitlab: endpoint = "https://\(cleanHost)/api/v4/user/keys"
        }
        guard let url = URL(string: endpoint), url.scheme == "https" else {
            return (false, "Could not build an HTTPS URL for \"\(cleanHost)\".")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch kind {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        case .gitlab:
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }

        let payload = [
            "title": title,
            "key": publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return (false, "Could not encode the upload request.")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return (false, error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            return (false, "Unexpected response from \(cleanHost).")
        }

        switch http.statusCode {
        case 201:
            return (true, "Public key uploaded to \(cleanHost).")
        case 401, 403:
            return (false, "Token rejected — check it has the api (GitLab) or admin:public_key (GitHub) scope.")
        case 400...499:
            // Re-uploading a key that is already on the host is the normal
            // idempotent path. GitHub reports it with 422, GitLab with 400 —
            // treat the duplicate message as success on any client error.
            let detail = errorMessage(from: data)
            let lower = detail.lowercased()
            if lower.contains("already in use") || lower.contains("has already been taken") {
                return (true, "This key is already on \(cleanHost) — you are all set.")
            }
            if http.statusCode == 422 {
                return (false, detail.isEmpty ? "The host rejected the key (HTTP 422)." : detail)
            }
            return (false, detail.isEmpty
                        ? "Upload failed (HTTP \(http.statusCode))."
                        : "Upload failed (HTTP \(http.statusCode)): \(detail)")
        default:
            let detail = errorMessage(from: data)
            return (false, detail.isEmpty
                        ? "Upload failed (HTTP \(http.statusCode))."
                        : "Upload failed (HTTP \(http.statusCode)): \(detail)")
        }
    }

    // MARK: - Error body parsing

    /// Extracts a human-readable message from a GitLab / GitHub error body.
    /// GitLab returns `{"message": "..."}` or `{"message": {field: [msgs]}}`;
    /// GitHub returns `{"message": "...", "errors": [{"message": "..."}]}`.
    private static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        }

        var parts: [String] = []

        if let message = dict["message"] as? String, !message.isEmpty {
            parts.append(message)
        } else if let fields = dict["message"] as? [String: Any] {
            for field in fields.keys.sorted() {
                for msg in stringList(fields[field]) {
                    parts.append("\(field) \(msg)")
                }
            }
        }
        if let errors = dict["errors"] as? [[String: Any]] {
            for err in errors {
                if let msg = err["message"] as? String, !msg.isEmpty {
                    parts.append(msg)
                }
            }
        }
        if parts.isEmpty, let error = dict["error"] as? String, !error.isEmpty {
            parts.append(error)
        }
        return parts.joined(separator: " — ")
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let single = value as? String { return [single] }
        if let array = value as? [Any] { return array.compactMap { $0 as? String } }
        return []
    }
}
