import Foundation
import SwiftUI

struct GPGKey: Identifiable {
    var id: String { keyID }
    var keyID: String     // long-format key id
    var uid: String       // "Name <email>"
    var created: String
}

@MainActor
final class GPGService: ObservableObject {
    @Published var keys: [GPGKey] = []
    @Published var available: Bool = true

    init() { reload() }

    func reload() {
        guard Shell.which("gpg") != nil else {
            available = false
            keys = []
            return
        }
        available = true
        let result = Shell.run("gpg", ["--list-secret-keys", "--keyid-format=long", "--with-colons"])
        keys = Self.parseColons(result.stdout)
    }

    static func parseColons(_ output: String) -> [GPGKey] {
        var result: [GPGKey] = []
        var currentID: String?
        var currentCreated = ""

        for line in output.components(separatedBy: "\n") {
            let fields = line.components(separatedBy: ":")
            guard let record = fields.first else { continue }

            if record == "sec" {
                currentID = fields.count > 4 ? fields[4] : nil
                if fields.count > 5, let epoch = Double(fields[5]) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    currentCreated = formatter.string(from: Date(timeIntervalSince1970: epoch))
                } else {
                    currentCreated = ""
                }
            } else if record == "uid", let id = currentID {
                let uid = fields.count > 9 ? fields[9] : ""
                result.append(GPGKey(keyID: id, uid: uid, created: currentCreated))
                currentID = nil  // only keep the primary uid
            }
        }
        return result
    }

    /// Creates an ed25519 sign-only key via a batch parameter file.
    func generate(name: String, email: String, passphrase: String) async -> CommandResult {
        var params = """
        %echo Generating GitKeys signing key
        Key-Type: eddsa
        Key-Curve: ed25519
        Key-Usage: sign
        Name-Real: \(name)
        Name-Email: \(email)
        Expire-Date: 0
        """
        if passphrase.isEmpty {
            params += "\n%no-protection\n%commit\n"
        } else {
            params += "\nPassphrase: \(passphrase)\n%commit\n"
        }

        let input = params
        let result = await Task.detached {
            Shell.run("gpg", ["--batch", "--gen-key"], input: input)
        }.value
        reload()
        return result
    }

    func exportPublic(_ key: GPGKey) -> String {
        let result = Shell.run("gpg", ["--armor", "--export", key.keyID])
        return result.ok ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.combinedOutput
    }

    /// Points global git config at this key for signed commits and tags.
    func configureGitSigning(_ key: GPGKey) -> CommandResult {
        _ = Shell.run("git", ["config", "--global", "user.signingkey", key.keyID])
        _ = Shell.run("git", ["config", "--global", "commit.gpgsign", "true"])
        _ = Shell.run("git", ["config", "--global", "tag.gpgsign", "true"])
        if let gpgPath = Shell.which("gpg") {
            _ = Shell.run("git", ["config", "--global", "gpg.program", gpgPath])
        }
        return Shell.run("git", ["config", "--global", "--get", "user.signingkey"])
    }
}
