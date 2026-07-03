import SwiftUI

struct GPGView: View {
    @EnvironmentObject var gpg: GPGService

    @State private var name = ""
    @State private var email = ""
    @State private var passphrase = ""
    @State private var busy = false
    @State private var exported = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GPG & Commit Signing")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Manage signing keys and tell git to sign your commits.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !gpg.available {
                    GPGMissingBanner()
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "key.fill",
                                  title: "Existing secret keys",
                                  subtitle: "Keys available in your local GPG keyring")

                    if gpg.keys.isEmpty {
                        EmptyStateView(icon: "key.slash",
                                       message: "No GPG secret keys found.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(gpg.keys) { key in
                                GPGKeyRow(key: key) {
                                    Task {
                                        exported = await gpg.exportPublic(key)
                                        flash("Exported public key for \(key.keyID)")
                                    }
                                } onSign: {
                                    Task {
                                        let result = await gpg.configureGitSigning(key)
                                        flash(result.ok
                                              ? "git will now sign commits with \(key.keyID)"
                                              : result.combinedOutput, error: !result.ok)
                                    }
                                }
                            }
                        }
                    }
                }
                .gkCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "plus.circle.fill",
                                  title: "Create a new signing key",
                                  subtitle: "Modern ed25519 key, ready for commit signing")

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Name") {
                            TextField("Your Name", text: $name).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Email") {
                            TextField("you@example.com", text: $email).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Passphrase") {
                            SecureField("optional — leave empty for none", text: $passphrase).textFieldStyle(.roundedBorder)
                        }
                        Button {
                            Task { await create() }
                        } label: {
                            GKBusyLabel(isBusy: busy) {
                                Label("Create GPG key", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.gkPrimary)
                        .disabled(busy || name.isEmpty || email.isEmpty || !gpg.available)
                        .padding(.top, 4)
                    }
                }
                .gkCard()

                if !exported.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            SectionHeader(icon: "square.and.arrow.up.fill",
                                          title: "Public key",
                                          subtitle: "Paste into your Git host's GPG settings")
                            Spacer()
                            Button {
                                copyToClipboard(exported)
                                flash("Copied public key")
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.gkSecondary)
                        }
                        MonospacedBox(text: exported).frame(height: 150)
                    }
                    .gkCard()
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                }

                if let message {
                    StatusBanner(text: message, isError: isError)
                }
            }
            .padding(GK.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(GK.spring, value: message)
            .animation(GK.spring, value: exported)
        }
        .task { await gpg.reload() }
    }

    private func create() async {
        busy = true
        message = nil
        let result = await gpg.generate(name: name, email: email, passphrase: passphrase)
        busy = false
        if result.ok {
            flash("Created GPG signing key for \(email)")
        } else {
            flash(result.combinedOutput.isEmpty ? "Failed to create key." : result.combinedOutput, error: true)
        }
    }

    private func flash(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }
}

// MARK: - "gpg not found" banner

/// Prominent orange-tinted warning card shown when gpg is missing from PATH.
private struct GPGMissingBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color.orange.opacity(0.85), Color.orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: Color.orange.opacity(0.35), radius: 5, x: 0, y: 2)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("gpg was not found on your PATH")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("Install it with")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("brew install gnupg")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.quaternary)
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: GK.cardCorner, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: GK.cardCorner, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: GK.cardCorner, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Key row

/// A single secret-key row: gradient seal tile, uid + metadata, trailing
/// export / use-for-signing actions. Highlights softly on hover.
private struct GPGKeyRow: View {
    let key: GPGKey
    let onExport: () -> Void
    let onSign: () -> Void

    @State private var hovering = false

    init(key: GPGKey, onExport: @escaping () -> Void, onSign: @escaping () -> Void) {
        self.key = key
        self.onExport = onExport
        self.onSign = onSign
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GK.accentGradient)
                    .shadow(color: GK.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.uid.isEmpty ? key.keyID : key.uid).font(.headline)
                Text("\(key.keyID) · created \(key.created)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.gkSecondary)

            Button(action: onSign) {
                Label("Use for signing", systemImage: "signature")
            }
            .buttonStyle(.gkSecondary)
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
