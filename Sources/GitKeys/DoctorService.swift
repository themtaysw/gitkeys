import Foundation
import SwiftUI

// MARK: - Model

/// One diagnostic result produced by the Doctor engine.
struct DoctorCheck: Identifiable {
    enum Status {
        case pass
        case warn
        case fail
    }

    enum Category: String, CaseIterable {
        case sshFiles = "SSH files"
        case agent = "Agent"
        case signing = "Signing"
    }

    /// Stable identifier — also used to dispatch the matching fix.
    let id: String
    let category: Category
    let title: String
    /// Human explanation of what was found.
    let detail: String
    let status: Status
    /// When set, the check has a one-click fix and this is the button label.
    let fixLabel: String?
}

// MARK: - Service

/// Runs the health checks and applies one-click fixes. Owned by `DoctorView`
/// as a `@StateObject`. The init is trivial by design — all filesystem and
/// subprocess work happens inside `runChecks()` / `fix(_:)` via detached tasks.
@MainActor
final class DoctorService: ObservableObject {
    @Published private(set) var checks: [DoctorCheck] = []
    @Published private(set) var isRunning = false
    @Published private(set) var hasRun = false

    var passCount: Int { checks.filter { $0.status == .pass }.count }
    var warnCount: Int { checks.filter { $0.status == .warn }.count }
    var failCount: Int { checks.filter { $0.status == .fail }.count }

    func runChecks() async {
        guard !isRunning else { return }
        isRunning = true
        let results = await Task.detached(priority: .userInitiated) {
            DoctorEngine.runAll()
        }.value
        checks = results
        hasRun = true
        isRunning = false
    }

    /// Applies the one-click fix for `check`, then re-runs every check so the
    /// list reflects the new state. The returned result carries a
    /// human-readable message in `stdout` (success) or `stderr` (failure).
    func fix(_ check: DoctorCheck) async -> CommandResult {
        let id = check.id
        let result = await Task.detached(priority: .userInitiated) {
            DoctorEngine.fix(id: id)
        }.value
        await runChecks()
        return result
    }
}

// MARK: - Engine
//
// Pure, stateless inspection and repair functions. Everything here is called
// via `Task.detached` because it touches the filesystem and spawns
// subprocesses; nothing in this enum may run on the main actor.

private enum DoctorEngine {

    enum CheckID {
        static let sshDirPerms   = "ssh.dir-permissions"
        static let keyPerms      = "ssh.key-permissions"
        static let strayFiles    = "ssh.stray-files"
        static let configSyntax  = "ssh.config-syntax"
        static let agentCoverage = "agent.coverage"
        static let signingEmail  = "signing.email-match"
        static let commitSigning = "signing.gpgsign"
    }

    static var sshDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    }

    // MARK: Entry points

    static func runAll() -> [DoctorCheck] {
        [
            checkSSHDirPermissions(),
            checkPrivateKeyPermissions(),
            checkStrayFiles(),
            checkConfigSyntax(),
            checkAgentCoverage(),
            checkSigningEmail(),
            checkCommitSigning()
        ]
    }

    static func fix(id: String) -> CommandResult {
        switch id {
        case CheckID.sshDirPerms:   return fixSSHDirPermissions()
        case CheckID.keyPerms:      return fixPrivateKeyPermissions()
        case CheckID.strayFiles:    return fixStrayFiles()
        case CheckID.agentCoverage: return fixAgentCoverage()
        case CheckID.signingEmail:  return fixSigningEmail()
        default:
            return failure("This check has no automatic fix.")
        }
    }

    // MARK: Shared helpers

    private static func success(_ message: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: message, stderr: "")
    }

    private static func failure(_ message: String) -> CommandResult {
        CommandResult(exitCode: 1, stdout: "", stderr: message)
    }

    private static func permissions(atPath path: String) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    private static func octal(_ permissions: Int) -> String {
        String(format: "%03o", permissions & 0o777)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func sshDirEntries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: sshDir.path)) ?? []).sorted()
    }

    /// Private keys in ~/.ssh = regular files whose `<name>.pub` sibling exists.
    private static func privateKeyPaths() -> [String] {
        var paths: [String] = []
        for entry in sshDirEntries() where entry.hasSuffix(".pub") {
            let name = String(entry.dropLast(4))
            guard !name.isEmpty else { continue }
            let url = sshDir.appendingPathComponent(name)
            if isRegularFile(url) { paths.append(url.path) }
        }
        return paths
    }

    private static func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func gitConfig(_ key: String) -> String {
        Shell.run("git", ["config", "--global", "--get", key])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 1. ~/.ssh directory permissions

    private static func checkSSHDirPermissions() -> DoctorCheck {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sshDir.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            return DoctorCheck(
                id: CheckID.sshDirPerms, category: .sshFiles,
                title: "~/.ssh directory permissions",
                detail: "~/.ssh does not exist yet. It will be created automatically when you generate your first key.",
                status: .warn, fixLabel: nil
            )
        }
        guard let perms = permissions(atPath: sshDir.path) else {
            return DoctorCheck(
                id: CheckID.sshDirPerms, category: .sshFiles,
                title: "~/.ssh directory permissions",
                detail: "Could not read the permissions of ~/.ssh.",
                status: .warn, fixLabel: nil
            )
        }
        if perms & 0o777 == 0o700 {
            return DoctorCheck(
                id: CheckID.sshDirPerms, category: .sshFiles,
                title: "~/.ssh directory permissions",
                detail: "Permissions are 700 — only you can read the directory.",
                status: .pass, fixLabel: nil
            )
        }
        return DoctorCheck(
            id: CheckID.sshDirPerms, category: .sshFiles,
            title: "~/.ssh directory permissions",
            detail: "Permissions are \(octal(perms)), but ssh expects 700. Loose permissions can make ssh refuse your keys and let other local users read the directory.",
            status: .fail, fixLabel: "Set to 700"
        )
    }

    private static func fixSSHDirPermissions() -> CommandResult {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: sshDir.path
            )
            return success("Set ~/.ssh permissions to 700.")
        } catch {
            return failure("Could not change permissions of ~/.ssh: \(error.localizedDescription)")
        }
    }

    // MARK: 2. Private key permissions

    private static func offendingPrivateKeys() -> [(path: String, perms: Int)] {
        privateKeyPaths().compactMap { path in
            guard let perms = permissions(atPath: path) else { return nil }
            return perms & 0o777 == 0o600 ? nil : (path, perms)
        }
    }

    private static func checkPrivateKeyPermissions() -> DoctorCheck {
        let keys = privateKeyPaths()
        guard !keys.isEmpty else {
            return DoctorCheck(
                id: CheckID.keyPerms, category: .sshFiles,
                title: "Private key permissions",
                detail: "No private keys found in ~/.ssh — nothing to check.",
                status: .pass, fixLabel: nil
            )
        }
        let offenders = offendingPrivateKeys()
        if offenders.isEmpty {
            let plural = keys.count == 1 ? "key is" : "keys are"
            return DoctorCheck(
                id: CheckID.keyPerms, category: .sshFiles,
                title: "Private key permissions",
                detail: "All \(keys.count) private \(plural) 600 — only you can read them.",
                status: .pass, fixLabel: nil
            )
        }
        let list = offenders
            .map { "\(fileName($0.path)) (\(octal($0.perms)))" }
            .joined(separator: ", ")
        return DoctorCheck(
            id: CheckID.keyPerms, category: .sshFiles,
            title: "Private key permissions",
            detail: "ssh refuses private keys that other users could read. Not 600: \(list).",
            status: .fail, fixLabel: "Set to 600"
        )
    }

    private static func fixPrivateKeyPermissions() -> CommandResult {
        let offenders = offendingPrivateKeys()
        guard !offenders.isEmpty else {
            return success("All private keys already have 600 permissions.")
        }
        var fixed: [String] = []
        var errors: [String] = []
        for offender in offenders {
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: offender.path
                )
                fixed.append(fileName(offender.path))
            } catch {
                errors.append("\(fileName(offender.path)): \(error.localizedDescription)")
            }
        }
        if errors.isEmpty {
            return success("Set permissions to 600 on \(fixed.joined(separator: ", ")).")
        }
        return failure("Could not fix all keys — \(errors.joined(separator: "; "))")
    }

    // MARK: 3. Stray / suspicious files

    /// Vim-accident patterns: names containing ':' (config:q, config:qs …) or
    /// stale-backup suffixes — except known_hosts.old, which ssh itself writes.
    private static func strayFileNames() -> [String] {
        sshDirEntries().filter { name in
            guard name != "known_hosts.old" else { return false }
            guard isRegularFile(sshDir.appendingPathComponent(name)) else { return false }
            if name.contains(":") { return true }
            return name.hasSuffix(".bak") || name.hasSuffix(".save") || name.hasSuffix(".old")
        }
    }

    private static func checkStrayFiles() -> DoctorCheck {
        let strays = strayFileNames()
        guard !strays.isEmpty else {
            return DoctorCheck(
                id: CheckID.strayFiles, category: .sshFiles,
                title: "Stray files in ~/.ssh",
                detail: "No leftover editor files or stale backups found.",
                status: .pass, fixLabel: nil
            )
        }
        return DoctorCheck(
            id: CheckID.strayFiles, category: .sshFiles,
            title: "Stray files in ~/.ssh",
            detail: "These look like editor accidents (a vim :q typed into the file name) or stale backups: \(strays.joined(separator: ", ")). They clutter ~/.ssh and can shadow your real config. Quarantining moves them into ~/.ssh/gitkeys-backups — nothing is deleted.",
            status: .warn, fixLabel: "Quarantine"
        )
    }

    private static func fixStrayFiles() -> CommandResult {
        let strays = strayFileNames()
        guard !strays.isEmpty else {
            return success("No stray files left to move.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let quarantine = sshDir
            .appendingPathComponent("gitkeys-backups")
            .appendingPathComponent("quarantine-\(formatter.string(from: Date()))")
        do {
            try FileManager.default.createDirectory(
                at: quarantine, withIntermediateDirectories: true
            )
        } catch {
            return failure("Could not create the quarantine folder: \(error.localizedDescription)")
        }
        var moved: [String] = []
        var errors: [String] = []
        for name in strays {
            do {
                try FileManager.default.moveItem(
                    at: sshDir.appendingPathComponent(name),
                    to: quarantine.appendingPathComponent(name)
                )
                moved.append(name)
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        let destination = tildeify(quarantine.path)
        if errors.isEmpty {
            return success("Moved \(moved.count) file\(moved.count == 1 ? "" : "s") to \(destination).")
        }
        var message = ""
        if !moved.isEmpty { message += "Moved \(moved.joined(separator: ", ")) to \(destination). " }
        message += "Could not move: \(errors.joined(separator: "; "))"
        return failure(message)
    }

    // MARK: 4. ssh-agent coverage

    private static func agentLoadedFingerprints() -> (fingerprints: Set<String>, error: String?) {
        let result = Shell.run("ssh-add", ["-l"])
        switch result.exitCode {
        case 0:
            var fingerprints = Set<String>()
            for line in result.stdout.components(separatedBy: "\n") {
                let fields = line.split(separator: " ")
                if fields.count >= 2 { fingerprints.insert(String(fields[1])) }
            }
            return (fingerprints, nil)
        case 1:
            // Agent reachable but has no identities loaded.
            return ([], nil)
        default:
            let output = result.combinedOutput
            return ([], output.isEmpty ? "Could not connect to ssh-agent." : output)
        }
    }

    private static func fingerprint(forPrivateKey path: String) -> String? {
        let result = Shell.run("ssh-keygen", ["-lf", path + ".pub"])
        guard result.ok else { return nil }
        let fields = result.stdout.split(separator: " ")
        return fields.count >= 2 ? String(fields[1]) : nil
    }

    private static func keysMissingFromAgent() -> (missing: [String], error: String?) {
        let keys = privateKeyPaths()
        guard !keys.isEmpty else { return ([], nil) }
        let (loaded, error) = agentLoadedFingerprints()
        if let error { return ([], error) }
        let missing = keys.filter { path in
            guard let keyPrint = fingerprint(forPrivateKey: path) else { return false }
            return !loaded.contains(keyPrint)
        }
        return (missing, nil)
    }

    private static func checkAgentCoverage() -> DoctorCheck {
        let keys = privateKeyPaths()
        guard !keys.isEmpty else {
            return DoctorCheck(
                id: CheckID.agentCoverage, category: .agent,
                title: "Keys loaded in ssh-agent",
                detail: "No keys in ~/.ssh, so there is nothing to load.",
                status: .pass, fixLabel: nil
            )
        }
        let (missing, error) = keysMissingFromAgent()
        if let error {
            return DoctorCheck(
                id: CheckID.agentCoverage, category: .agent,
                title: "Keys loaded in ssh-agent",
                detail: "Could not talk to ssh-agent: \(error)",
                status: .warn, fixLabel: nil
            )
        }
        if missing.isEmpty {
            let plural = keys.count == 1 ? "key is" : "keys are"
            return DoctorCheck(
                id: CheckID.agentCoverage, category: .agent,
                title: "Keys loaded in ssh-agent",
                detail: "All \(keys.count) \(plural) loaded in ssh-agent.",
                status: .pass, fixLabel: nil
            )
        }
        let names = missing.map(fileName).joined(separator: ", ")
        return DoctorCheck(
            id: CheckID.agentCoverage, category: .agent,
            title: "Keys loaded in ssh-agent",
            detail: "Not loaded in ssh-agent: \(names). Pushes and pulls with these keys will prompt for a passphrase every time — or fail silently in GUI apps.",
            status: .warn, fixLabel: "Load into agent"
        )
    }

    private static func fixAgentCoverage() -> CommandResult {
        let (missing, error) = keysMissingFromAgent()
        if let error { return failure("Could not talk to ssh-agent: \(error)") }
        guard !missing.isEmpty else {
            return success("Every key is already loaded in ssh-agent.")
        }
        var loaded: [String] = []
        var stubborn: [String] = []
        for path in missing {
            let result = Shell.run("ssh-add", ["--apple-use-keychain", path])
            if result.ok {
                loaded.append(fileName(path))
            } else {
                stubborn.append(path)
            }
        }
        if stubborn.isEmpty {
            return success("Loaded into ssh-agent: \(loaded.joined(separator: ", ")).")
        }
        // Keys with passphrases need an interactive prompt, which requires a
        // real terminal — hand the user the exact command to run.
        let command = "ssh-add --apple-use-keychain "
            + stubborn
                .map { path -> String in
                    let tidy = tildeify(path)
                    return tidy.contains(" ") ? "\"\(tidy)\"" : tidy
                }
                .joined(separator: " ")
        var message = ""
        if !loaded.isEmpty { message += "Loaded \(loaded.joined(separator: ", ")). " }
        message += "The remaining key\(stubborn.count == 1 ? "" : "s") likely need a passphrase, which macOS only prompts for in a terminal. Run this in Terminal: \(command)"
        return failure(message)
    }

    // MARK: 5. Signing email matches the key's UID (the flagship check)

    private static func extractEmail(fromUID uid: String) -> String? {
        if let open = uid.lastIndex(of: "<"), let close = uid.lastIndex(of: ">"), open < close {
            let email = String(uid[uid.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            return email.isEmpty ? nil : email
        }
        let trimmed = uid.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && !trimmed.contains(" ") ? trimmed : nil
    }

    private static func uidEmails(forSigningKey keyID: String) -> [String] {
        let result = Shell.run("gpg", ["--list-keys", "--with-colons", keyID])
        guard result.ok else { return [] }
        var emails: [String] = []
        for line in result.stdout.components(separatedBy: "\n") where line.hasPrefix("uid:") {
            let fields = line.components(separatedBy: ":")
            guard fields.count > 9, let email = extractEmail(fromUID: fields[9]) else { continue }
            if !emails.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) {
                emails.append(email)
            }
        }
        return emails
    }

    private static func signingEmailCheck(_ detail: String, _ status: DoctorCheck.Status,
                                          fixLabel: String? = nil) -> DoctorCheck {
        DoctorCheck(
            id: CheckID.signingEmail, category: .signing,
            title: "Signing email matches commit email",
            detail: detail, status: status, fixLabel: fixLabel
        )
    }

    private static func checkSigningEmail() -> DoctorCheck {
        guard Shell.which("git") != nil else {
            return signingEmailCheck(
                "git was not found on PATH, so the signing configuration could not be inspected.",
                .warn
            )
        }
        let signingKey = gitConfig("user.signingkey")
        guard !signingKey.isEmpty else {
            return signingEmailCheck(
                "No global signing key is configured, so there is nothing to mismatch. Set one up in the GPG tab to get Verified badges on your commits.",
                .pass
            )
        }
        if gitConfig("gpg.format").lowercased() == "ssh" {
            return signingEmailCheck(
                "Commits are signed with an SSH key (gpg.format = ssh), so GPG UID matching does not apply. Make sure user.email is a verified email on your Git host and the key is registered there as a signing key.",
                .pass
            )
        }
        guard Shell.which("gpg") != nil else {
            return signingEmailCheck(
                "user.signingkey is set to \(signingKey), but gpg was not found on PATH — git cannot sign commits until GnuPG is installed.",
                .warn
            )
        }
        let emails = uidEmails(forSigningKey: signingKey)
        guard !emails.isEmpty else {
            return signingEmailCheck(
                "Could not read any UID emails from signing key \(signingKey). The key may be missing from your GPG keyring.",
                .warn
            )
        }
        let userEmail = gitConfig("user.email")
        guard !userEmail.isEmpty else {
            return signingEmailCheck(
                "git user.email is not set, but commits are signed with key \(signingKey) (\(emails[0])). Git hosts only show a Verified badge when the committer email matches a UID on the signing key and is a verified email on the host.",
                .fail, fixLabel: "Use key's email"
            )
        }
        if emails.contains(where: { $0.caseInsensitiveCompare(userEmail) == .orderedSame }) {
            return signingEmailCheck(
                "user.email (\(userEmail)) matches a UID on signing key \(signingKey). For Verified badges, make sure it is also a verified email on your Git host.",
                .pass
            )
        }
        return signingEmailCheck(
            "user.email is \(userEmail), but signing key \(signingKey) only carries UID email\(emails.count == 1 ? "" : "s") \(emails.joined(separator: ", ")). GitHub and GitLab mark such commits Unverified: the committer email must match a UID on the signing key and be a verified email on the Git host.",
            .fail, fixLabel: "Use key's email"
        )
    }

    private static func fixSigningEmail() -> CommandResult {
        let signingKey = gitConfig("user.signingkey")
        guard !signingKey.isEmpty else {
            return failure("No global signing key is configured anymore.")
        }
        guard let primary = uidEmails(forSigningKey: signingKey).first else {
            return failure("Could not read a UID email from signing key \(signingKey).")
        }
        let result = Shell.run("git", ["config", "--global", "user.email", primary])
        guard result.ok else {
            let output = result.combinedOutput
            return failure(output.isEmpty ? "git config failed." : output)
        }
        return success("Set git user.email to \(primary). Remember to verify this address on your Git host too.")
    }

    // MARK: 6. commit.gpgsign status (informational)

    private static func checkCommitSigning() -> DoctorCheck {
        guard Shell.which("git") != nil else {
            return DoctorCheck(
                id: CheckID.commitSigning, category: .signing,
                title: "Automatic commit signing",
                detail: "git was not found on PATH, so commit.gpgsign could not be inspected.",
                status: .warn, fixLabel: nil
            )
        }
        let gpgsign = gitConfig("commit.gpgsign").lowercased()
        let program = gitConfig("gpg.program")

        var parts: [String] = []
        var status = DoctorCheck.Status.pass

        if gpgsign == "true" {
            parts.append("commit.gpgsign is on — every commit is signed automatically.")
        } else {
            status = .warn
            parts.append(
                gpgsign.isEmpty
                ? "commit.gpgsign is not set — commits are only signed when you pass -S."
                : "commit.gpgsign is \(gpgsign) — commits are only signed when you pass -S."
            )
        }

        if program.isEmpty {
            if Shell.which("gpg") != nil {
                parts.append("gpg.program is unset; git will use gpg from PATH (found).")
            } else {
                status = .warn
                parts.append("gpg.program is unset and gpg was not found on PATH.")
            }
        } else if FileManager.default.isExecutableFile(atPath: program) {
            parts.append("gpg.program resolves to \(tildeify(program)).")
        } else {
            status = .warn
            parts.append("gpg.program points to \(program), which is missing or not executable.")
        }

        return DoctorCheck(
            id: CheckID.commitSigning, category: .signing,
            title: "Automatic commit signing",
            detail: parts.joined(separator: " "),
            status: status, fixLabel: nil
        )
    }

    // MARK: 7. ~/.ssh/config syntax sanity

    private static func checkConfigSyntax() -> DoctorCheck {
        let result = Shell.run("ssh", ["-G", "localhost"])
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = stderr.components(separatedBy: "\n").prefix(3).joined(separator: "\n")

        if !result.ok {
            var detail = "ssh could not parse your configuration (exit code \(result.exitCode))."
            if !excerpt.isEmpty { detail += "\n\(excerpt)" }
            return DoctorCheck(
                id: CheckID.configSyntax, category: .sshFiles,
                title: "~/.ssh/config syntax",
                detail: detail, status: .fail, fixLabel: nil
            )
        }

        let lowered = stderr.lowercased()
        let errorHints = ["bad ", "bad configuration", "error", "unknown", "line "]
        if !stderr.isEmpty, errorHints.contains(where: { lowered.contains($0) }) {
            return DoctorCheck(
                id: CheckID.configSyntax, category: .sshFiles,
                title: "~/.ssh/config syntax",
                detail: "ssh reported configuration problems:\n\(excerpt)",
                status: .fail, fixLabel: nil
            )
        }

        var detail = "ssh -G parsed your configuration cleanly."
        if !excerpt.isEmpty { detail += " Note: \(excerpt)" }
        return DoctorCheck(
            id: CheckID.configSyntax, category: .sshFiles,
            title: "~/.ssh/config syntax",
            detail: detail, status: .pass, fixLabel: nil
        )
    }
}
