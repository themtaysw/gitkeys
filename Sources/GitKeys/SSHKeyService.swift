import Foundation
import SwiftUI

struct SSHKey: Identifiable {
    var id: String { path }
    var name: String          // private key filename, e.g. id_ed25519
    var path: String          // full path to the private key
    var publicKeyPath: String
    var type: String          // e.g. ssh-ed25519
    var comment: String
    var publicKey: String     // full public-key line
}

@MainActor
final class SSHKeyService: ObservableObject {
    @Published var keys: [SSHKey] = []

    let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

    init() { reload() }

    /// Scans ~/.ssh for `.pub` files. Only public keys are ever read — private
    /// key contents are never opened or displayed.
    func reload() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: sshDir.path) else {
            keys = []
            return
        }

        var found: [SSHKey] = []
        for item in items where item.hasSuffix(".pub") {
            let pubURL = sshDir.appendingPathComponent(item)
            guard let raw = try? String(contentsOf: pubURL, encoding: .utf8) else { continue }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            let type = parts.first ?? "key"
            let comment = parts.count > 2 ? parts[2] : ""
            let privName = String(item.dropLast(4))   // strip ".pub"
            let privPath = sshDir.appendingPathComponent(privName).path

            found.append(SSHKey(
                name: privName, path: privPath, publicKeyPath: pubURL.path,
                type: type, comment: comment, publicKey: line
            ))
        }
        keys = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Generates an ed25519 key pair. Refuses to overwrite an existing file.
    func generate(name: String, comment: String, passphrase: String) async -> CommandResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return CommandResult(exitCode: 1, stdout: "", stderr: "Please provide a file name.")
        }
        let target = sshDir.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: target.path) {
            return CommandResult(exitCode: 1, stdout: "",
                                 stderr: "A key named \"\(trimmed)\" already exists in ~/.ssh.")
        }

        try? FileManager.default.createDirectory(
            at: sshDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let path = target.path
        let result = await Task.detached {
            Shell.run("ssh-keygen", ["-t", "ed25519", "-f", path, "-C", comment, "-N", passphrase])
        }.value
        reload()
        return result
    }
}
