import Foundation
import SwiftUI

// MARK: - Model

/// One folder-scoped git identity: everything under `folder` commits as
/// `name <email>`, optionally signed with `signingKey`. Backed by a profile
/// file at `path` that is wired into `~/.gitconfig` via an
/// `[includeIf "gitdir:…"]` section.
struct IdentityProfile: Identifiable, Equatable, Sendable {
    var folder: String      // gitdir pattern, e.g. "~/work/" (trailing slash)
    var name: String
    var email: String
    var signingKey: String  // empty when the profile doesn't set one
    var path: String        // absolute path of the profile .gitconfig file
    /// Exact global-config section (e.g. `includeif.gitdir:~/work/`) as it was
    /// discovered — passed verbatim to `git config --remove-section`.
    var section: String

    var id: String { section + "|" + path }

    init(folder: String, name: String, email: String,
         signingKey: String = "", path: String = "", section: String = "") {
        self.folder = folder
        self.name = name
        self.email = email
        self.signingKey = signingKey
        self.path = path
        self.section = section.isEmpty ? "includeIf.gitdir:\(folder)" : section
    }
}

// MARK: - Service

/// Manages per-folder git identities via git conditional includes.
///
/// Profile files live in `~/.config/gitkeys/identities/<slug>.gitconfig` and
/// are attached to the global config with
/// `[includeIf "gitdir:<folder>/"] path = <profile>`. All subprocess and file
/// work runs off the main thread; only published results land on the actor.
@MainActor
final class IdentityService: ObservableObject {
    @Published var profiles: [IdentityProfile] = []

    // MARK: Paths & normalization (pure helpers — also used by the view)

    nonisolated static var identitiesDir: String {
        expandTilde("~/.config/gitkeys/identities")
    }

    nonisolated static var backupsDir: String {
        expandTilde("~/.config/gitkeys/backups")
    }

    nonisolated static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Normalizes a folder for use as a `gitdir:` pattern: trimmed, ~-relative
    /// when under the home directory, and always ending in "/" so git matches
    /// every repository underneath it.
    nonisolated static func normalizeFolder(_ raw: String) -> String {
        var folder = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if folder.hasPrefix(home) {
            folder = "~" + folder.dropFirst(home.count)
        }
        if !folder.hasSuffix("/") { folder += "/" }
        return folder
    }

    /// Turns a folder pattern into a safe profile filename stem,
    /// e.g. "~/Work/Clients/" → "work-clients".
    nonisolated static func slugify(_ folder: String) -> String {
        var slug = ""
        var previousWasDash = true // suppress leading dashes
        for scalar in folder.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug += String(Character(scalar)).lowercased()
                previousWasDash = false
            } else if !previousWasDash {
                slug += "-"
                previousWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "profile" : slug
    }

    /// Short, stable disambiguator derived from the exact folder pattern.
    /// slugify() collapses case and punctuation, so "~/Work/", "~/work/" and
    /// "~/Work Clients/" vs "~/work-clients/" would otherwise share one
    /// profile file — and one folder's save() would silently overwrite the
    /// other's identity. FNV-1a over UTF-8, hex-encoded to 6 chars.
    nonisolated static func shortHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%06x", hash & 0xFFFFFF)
    }

    /// Profile filename for a normalized folder pattern, unique per exact
    /// pattern: "~/Work/Clients/" → "work-clients-a1b2c3.gitconfig".
    nonisolated static func profileFileName(for folder: String) -> String {
        slugify(folder) + "-" + shortHash(folder) + ".gitconfig"
    }

    // MARK: Reload

    /// Discovers profiles by scanning the global config for includeIf sections
    /// whose path points inside `~/.config/gitkeys/identities/`.
    func reload() async {
        profiles = await Task.detached { Self.discoverProfiles() }.value
    }

    private nonisolated static func discoverProfiles() -> [IdentityProfile] {
        // -z: NUL-separated records ("key\nvalue\0") so folders with spaces parse safely.
        // Section/variable names are reported lowercased; subsections keep their case.
        let result = Shell.run("git", ["config", "--global", "-z", "--get-regexp", "includeif"])
        guard result.ok, !result.stdout.isEmpty else { return [] } // exit 1 = no matches

        let dirPrefix = identitiesDir + "/"
        var found: [IdentityProfile] = []
        var seen = Set<String>()

        for record in result.stdout.components(separatedBy: "\0") where !record.isEmpty {
            guard let newline = record.firstIndex(of: "\n") else { continue }
            let key = String(record[..<newline])
            let value = String(record[record.index(after: newline)...])

            let lowered = key.lowercased()
            guard lowered.hasPrefix("includeif."), lowered.hasSuffix(".path") else { continue }

            // "includeif.gitdir:~/work/.path" → section "includeif.gitdir:~/work/"
            let section = String(key.dropLast(".path".count))
            let inner = String(section.dropFirst("includeif.".count))
            let innerLowered = inner.lowercased()

            let folder: String
            if innerLowered.hasPrefix("gitdir/i:") {
                folder = String(inner.dropFirst("gitdir/i:".count))
            } else if innerLowered.hasPrefix("gitdir:") {
                folder = String(inner.dropFirst("gitdir:".count))
            } else {
                continue // onbranch: / hasconfig: conditions aren't ours
            }

            let filePath = (expandTilde(value) as NSString).standardizingPath
            guard filePath.hasPrefix(dirPrefix) else { continue } // not managed by GitKeys
            guard seen.insert(section + "|" + filePath).inserted else { continue } // duplicate multivar entry

            func read(_ key: String) -> String {
                let r = Shell.run("git", ["config", "-f", filePath, "--get", key])
                return r.ok ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }

            found.append(IdentityProfile(folder: folder,
                                         name: read("user.name"),
                                         email: read("user.email"),
                                         signingKey: read("user.signingkey"),
                                         path: filePath,
                                         section: section))
        }

        return found.sorted {
            $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending
        }
    }

    // MARK: Save

    /// Writes the profile file and wires it into `~/.gitconfig`. When the
    /// folder already contains a git repository, verifies that git actually
    /// resolves the new email there.
    func save(profile: IdentityProfile) async -> (ok: Bool, message: String) {
        let folder = Self.normalizeFolder(profile.folder)
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let signingKey = profile.signingKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !folder.isEmpty else { return (false, "Choose a folder for this profile.") }
        guard !name.isEmpty, !email.isEmpty else { return (false, "Name and email are both required.") }

        let outcome = await Task.detached { () -> (Bool, String) in
            let dir = Self.identitiesDir
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return (false, "Could not create \(tildeify(dir)): \(error.localizedDescription)")
            }

            let filePath = dir + "/" + Self.profileFileName(for: folder)

            // Write the profile values.
            let writes: [(String, String?)] = [
                ("user.name", name),
                ("user.email", email),
                ("user.signingkey", signingKey.isEmpty ? nil : signingKey)
            ]
            for (key, value) in writes {
                if let value {
                    let r = Shell.run("git", ["config", "-f", filePath, key, value])
                    guard r.ok else {
                        return (false, "Could not write \(key): \(r.combinedOutput)")
                    }
                } else {
                    // Clear a previously-set signing key; failure just means it wasn't set.
                    _ = Shell.run("git", ["config", "-f", filePath, "--unset", key])
                }
            }

            // Wire the conditional include into the global config.
            let wire = Shell.run("git", ["config", "--global",
                                         "includeIf.gitdir:\(folder).path",
                                         tildeify(filePath)])
            guard wire.ok else {
                return (false, "Could not update ~/.gitconfig: \(wire.combinedOutput)")
            }

            // Verify against a real repo when the folder itself is one.
            let expandedFolder = Self.expandTilde(folder)
            if FileManager.default.fileExists(atPath: expandedFolder + ".git") {
                let check = Shell.run("git", ["-C", expandedFolder, "config", "user.email"])
                let effective = check.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if check.ok, effective == email {
                    return (true, "Profile saved — verified that commits under \(folder) now use \(email).")
                }
                if check.ok {
                    return (false, "Profile saved, but the repo at \(folder) still resolves to "
                            + (effective.isEmpty ? "no email" : "“\(effective)”")
                            + " — a local .git/config override may take precedence.")
                }
            }
            return (true, "Profile saved. Repositories under \(folder) will commit as \(name) <\(email)>.")
        }.value

        await reload()
        return outcome
    }

    // MARK: Remove

    /// Unwires the includeIf section from the global config and moves the
    /// profile file into `~/.config/gitkeys/backups/` (never deletes it).
    func remove(profile: IdentityProfile) async -> (ok: Bool, message: String) {
        let section = profile.section
        let path = profile.path
        let folder = profile.folder

        let outcome = await Task.detached { () -> (Bool, String) in
            // `--remove-section` matches the on-disk header casing exactly when a
            // subsection is present (verified on git 2.48), while `--get-regexp`
            // always reports the section name lowercased. Try the discovered form
            // first, then the camelCase "includeIf" form GitKeys itself writes.
            var candidates = [section]
            let lowered = section.lowercased()
            if lowered.hasPrefix("includeif.") {
                let camel = "includeIf" + section.dropFirst("includeif".count)
                if camel != section { candidates.append(camel) }
            }
            var removal = CommandResult(exitCode: -1, stdout: "", stderr: "")
            for candidate in candidates {
                removal = Shell.run("git", ["config", "--global", "--remove-section", candidate])
                if removal.ok { break }
            }

            var backedUp = false
            let fm = FileManager.default
            if fm.fileExists(atPath: path) {
                do {
                    try fm.createDirectory(atPath: Self.backupsDir, withIntermediateDirectories: true)
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyyMMdd-HHmmss"
                    let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                    let destination = Self.backupsDir + "/" + stem + "-"
                        + formatter.string(from: Date()) + ".gitconfig"
                    try fm.moveItem(atPath: path, toPath: destination)
                    backedUp = true
                } catch {
                    return (false, "Unwired \(folder), but could not back up its profile file: \(error.localizedDescription)")
                }
            }

            if !removal.ok && !backedUp {
                let detail = removal.combinedOutput
                return (false, detail.isEmpty ? "Nothing to remove for \(folder)." : detail)
            }
            return (true, "Removed the \(folder) identity"
                    + (backedUp ? " — profile file backed up to \(tildeify(Self.backupsDir))." : "."))
        }.value

        await reload()
        return outcome
    }

    // MARK: Effective identity

    /// Asks git what identity actually applies inside `folder`. Meaningful
    /// only when the folder is (or is inside) a repository; otherwise git
    /// falls back to global values or errors, and empty strings come back.
    func effectiveIdentity(for folder: String) async -> (name: String, email: String, signingKey: String) {
        let expanded = Self.expandTilde(folder)
        return await Task.detached { () -> (String, String, String) in
            func read(_ key: String) -> String {
                let r = Shell.run("git", ["-C", expanded, "config", key])
                return r.ok ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            return (read("user.name"), read("user.email"), read("user.signingkey"))
        }.value
    }
}
