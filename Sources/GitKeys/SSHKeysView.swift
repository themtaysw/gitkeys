import SwiftUI

struct SSHKeysView: View {
    @EnvironmentObject var keyService: SSHKeyService

    @State private var newName = "id_gitlab_spendee"
    @State private var comment = ""
    @State private var passphrase = ""
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH Keys")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Inspect the keys in ~/.ssh and generate new ones.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // MARK: Existing keys
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        icon: "folder.badge.person.crop",
                        title: "Existing keys",
                        subtitle: "Key pairs found in ~/.ssh"
                    )

                    if keyService.keys.isEmpty {
                        EmptyStateView(
                            icon: "key.slash",
                            message: "No SSH keys found in ~/.ssh.\nGenerate one below to get started."
                        )
                    } else {
                        VStack(spacing: 4) {
                            ForEach(keyService.keys) { key in
                                SSHKeyRow(key: key) {
                                    copyToClipboard(key.publicKey)
                                    flash("Copied public key for \(key.name)")
                                }
                            }
                        }
                    }
                }
                .gkCard()

                // MARK: Generate a new key
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        icon: "plus.circle.fill",
                        title: "Generate a new key",
                        subtitle: "Creates a modern ed25519 key pair"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("File name") {
                            TextField("id_gitlab_spendee", text: $newName).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Comment") {
                            TextField("you@example.com", text: $comment).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Passphrase") {
                            SecureField("optional — leave empty for none", text: $passphrase).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 12) {
                            Button {
                                Task { await generate() }
                            } label: {
                                GKBusyLabel(isBusy: busy) {
                                    Label("Generate key", systemImage: "sparkles")
                                        .frame(minWidth: 88)
                                }
                            }
                            .buttonStyle(.gkPrimary)
                            .disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty)

                            Text("Saves to ~/.ssh/\(newName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .gkCard()

                if let message {
                    StatusBanner(text: message, isError: isError)
                }
            }
            .padding(GK.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(GK.spring, value: message)
        }
        .onAppear { keyService.reload() }
    }

    private func generate() async {
        busy = true
        message = nil
        let result = await keyService.generate(
            name: newName, comment: comment, passphrase: passphrase
        )
        busy = false
        if result.ok {
            flash("Created ~/.ssh/\(newName.trimmingCharacters(in: .whitespaces))")
        } else {
            flash(result.combinedOutput.isEmpty ? "Failed to create key." : result.combinedOutput, error: true)
        }
    }

    private func flash(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }
}

// MARK: - Key row

/// A single SSH key entry: gradient key tile, name + metadata, copy action.
/// Highlights softly on hover.
private struct SSHKeyRow: View {
    let key: SSHKey
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GK.accentGradient)
                    .shadow(color: GK.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(key.comment.isEmpty ? key.type : "\(key.type) · \(key.comment)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                onCopy()
            } label: {
                Label("Copy public key", systemImage: "doc.on.doc")
            }
            .buttonStyle(.gkSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
