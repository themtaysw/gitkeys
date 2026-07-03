import Foundation
import SwiftUI

@MainActor
final class SSHConfigStore: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var preamble: String = ""
    @Published var lastError: String?
    @Published var lastSavedBackup: String?

    let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    var configURL: URL { sshDir.appendingPathComponent("config") }

    // MARK: - Loading

    func load() {
        hosts = []
        preamble = ""
        lastError = nil
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        parse(content)
    }

    private func parse(_ content: String) {
        var pre: [String] = []
        var current: SSHHost?
        var result: [SSHHost] = []
        var seenHost = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            let isHostLine = lower == "host" || lower.hasPrefix("host ") || lower.hasPrefix("host\t")

            if isHostLine {
                seenHost = true
                if let host = current { result.append(host) }
                let patterns = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                current = SSHHost(patterns: patterns, options: [])
                continue
            }

            if !seenHost {
                pre.append(line)
                continue
            }

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                current?.options.append(SSHOption(keyword: line, value: "", isRaw: true))
            } else if let (keyword, value) = Self.splitOption(trimmed) {
                current?.options.append(SSHOption(keyword: keyword, value: value))
            } else {
                current?.options.append(SSHOption(keyword: line, value: "", isRaw: true))
            }
        }
        if let host = current { result.append(host) }

        preamble = pre.joined(separator: "\n")
        hosts = result
    }

    private static func splitOption(_ line: String) -> (String, String)? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
        guard let first = parts.first else { return nil }
        let keyword = String(first)
        let value = parts.dropFirst().joined(separator: " ")
        return (keyword, value)
    }

    // MARK: - Editing helpers

    func addOrReplaceHost(_ host: SSHHost) {
        if let idx = hosts.firstIndex(where: {
            $0.patterns.caseInsensitiveCompare(host.patterns) == .orderedSame
        }) {
            hosts[idx] = host
        } else {
            hosts.append(host)
        }
    }

    // MARK: - Saving

    func serialize() -> String {
        var out = ""
        if !preamble.isEmpty {
            out += preamble
            if !preamble.hasSuffix("\n") { out += "\n" }
        }
        for host in hosts {
            out += "Host \(host.patterns)\n"
            for opt in host.options {
                if opt.isRaw {
                    out += "\(opt.keyword)\n"
                } else {
                    let value = opt.value.trimmingCharacters(in: .whitespaces)
                    out += "    \(opt.keyword) \(value)\n"
                }
            }
        }
        return out
    }

    func save() {
        lastError = nil
        lastSavedBackup = nil

        try? FileManager.default.createDirectory(
            at: sshDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if FileManager.default.fileExists(atPath: configURL.path) {
            let backupDir = sshDir.appendingPathComponent("gitkeys-backups")
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backupURL = backupDir.appendingPathComponent("config-\(Self.timestamp()).bak")
            try? FileManager.default.copyItem(at: configURL, to: backupURL)
            lastSavedBackup = backupURL.path
        }

        do {
            try serialize().write(to: configURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: configURL.path
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
