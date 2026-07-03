import SwiftUI
import AppKit

struct IdentitiesView: View {
    @StateObject private var service = IdentityService()
    @EnvironmentObject var gpg: GPGService

    @State private var folder = ""
    @State private var name = ""
    @State private var email = ""
    @State private var signingKeyID = ""   // "" = none
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Identities")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Right name, email and signing key per folder — never commit as the wrong you again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                profilesCard
                addCard
                howItWorksCard

                if let message {
                    StatusBanner(text: message, isError: isError)
                }
            }
            .padding(GK.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(GK.spring, value: message)
            .animation(GK.spring, value: service.profiles)
        }
        .task {
            await service.reload()
            await gpg.reload()
        }
    }

    // MARK: - Profiles

    private var profilesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "person.2.fill",
                          title: "Profiles",
                          subtitle: "Folder-scoped identities wired into your global git config")

            if service.profiles.isEmpty {
                EmptyStateView(icon: "person.crop.circle.badge.questionmark",
                               message: "No folder identities yet.\nAdd one below — e.g. ~/work with your work email — and git will switch automatically.")
            } else {
                VStack(spacing: 8) {
                    ForEach(service.profiles) { profile in
                        IdentityProfileRow(profile: profile) {
                            Task { await remove(profile) }
                        }
                    }
                }
            }
        }
        .gkCard()
    }

    // MARK: - Add a profile

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "plus.circle.fill",
                          title: "Add a profile",
                          subtitle: "Pick a folder, then the identity to use inside it")

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        TextField("~/work", text: $folder)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            chooseFolder()
                        } label: {
                            Label("Choose…", systemImage: "folder")
                        }
                        .buttonStyle(.gkSecondary)
                    }
                }
                LabeledContent("Name") {
                    TextField("Your Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Email") {
                    TextField("you@company.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Signing key") {
                    Picker("", selection: $signingKeyID) {
                        Text("None").tag("")
                        ForEach(gpg.keys) { key in
                            Text("\(key.uid) — \(key.keyID)").tag(key.keyID)
                        }
                    }
                    .labelsHidden()
                }

                Button {
                    Task { await add() }
                } label: {
                    GKBusyLabel(isBusy: busy) {
                        Label("Add profile", systemImage: "person.badge.plus")
                    }
                }
                .buttonStyle(.gkPrimary)
                .disabled(busy
                          || folder.trimmingCharacters(in: .whitespaces).isEmpty
                          || name.trimmingCharacters(in: .whitespaces).isEmpty
                          || email.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 4)
            }
        }
        .gkCard()
    }

    // MARK: - How it works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "info.circle.fill",
                          title: "How it works",
                          subtitle: "Git conditional includes, managed for you")

            Text("GitKeys writes each profile to its own file and points your global git config at it with an includeIf rule. Whenever git runs inside a repository under that folder, the profile's user.name, user.email and user.signingkey apply automatically — the trailing slash makes the rule cover every repository inside the folder. Repos elsewhere are untouched.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MonospacedBox(text: generatedBlock)
                .frame(height: 190)
        }
        .gkCard()
    }

    /// Live preview of the config git ends up with, built from the form
    /// fields (placeholders when empty).
    private var generatedBlock: String {
        let pattern = IdentityService.normalizeFolder(
            folder.trimmingCharacters(in: .whitespaces).isEmpty ? "~/work" : folder)
        let fileName = IdentityService.profileFileName(for: pattern)
        let previewName = name.isEmpty ? "Your Name" : name
        let previewEmail = email.isEmpty ? "you@company.com" : email

        var block = """
        # ~/.gitconfig
        [includeIf "gitdir:\(pattern)"]
            path = ~/.config/gitkeys/identities/\(fileName)

        # ~/.config/gitkeys/identities/\(fileName)
        [user]
            name = \(previewName)
            email = \(previewEmail)
        """
        if !signingKeyID.isEmpty {
            block += "\n    signingkey = \(signingKeyID)"
        }
        return block
    }

    // MARK: - Actions

    private func add() async {
        busy = true
        message = nil
        let profile = IdentityProfile(folder: folder, name: name,
                                      email: email, signingKey: signingKeyID)
        let result = await service.save(profile: profile)
        busy = false
        flash(result.message, error: !result.ok)
        if result.ok {
            folder = ""
            name = ""
            email = ""
            signingKeyID = ""
        }
    }

    private func remove(_ profile: IdentityProfile) async {
        let result = await service.remove(profile: profile)
        flash(result.message, error: !result.ok)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder this identity applies to"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            folder = tildeify(url.path)
        }
    }

    private func flash(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }
}

// MARK: - Profile row

/// A single identity row: orange folder tile, monospaced folder pattern,
/// "Name <email>" plus the signing key when set, and a trailing destructive
/// Remove action. Highlights softly on hover.
private struct IdentityProfileRow: View {
    let profile: IdentityProfile
    let onRemove: () -> Void

    @State private var hovering = false

    init(profile: IdentityProfile, onRemove: @escaping () -> Void) {
        self.profile = profile
        self.onRemove = onRemove
    }

    private var identityLine: String {
        if profile.name.isEmpty && profile.email.isEmpty {
            return "No identity set in the profile file"
        }
        return "\(profile.name) <\(profile.email)>"
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "folder.fill", color: .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.folder)
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(profile.folder)
                Text(identityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !profile.signingKey.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                        Text(profile.signingKey)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.gkDestructive)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
        )
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
