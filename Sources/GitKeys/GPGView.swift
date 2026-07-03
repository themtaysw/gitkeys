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
            VStack(alignment: .leading, spacing: 18) {
                Text("GPG & Commit Signing").font(.largeTitle.bold())

                if !gpg.available {
                    Label("gpg was not found on your PATH. Install it with: brew install gnupg",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                GroupBox("Existing secret keys") {
                    if gpg.keys.isEmpty {
                        Text("No GPG secret keys found.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(gpg.keys) { key in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key.uid.isEmpty ? key.keyID : key.uid).font(.headline)
                                        Text("\(key.keyID) · created \(key.created)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        Task {
                                            exported = await gpg.exportPublic(key)
                                            flash("Exported public key for \(key.keyID)")
                                        }
                                    } label: {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                    Button {
                                        Task {
                                            let result = await gpg.configureGitSigning(key)
                                            flash(result.ok
                                                  ? "git will now sign commits with \(key.keyID)"
                                                  : result.combinedOutput, error: !result.ok)
                                        }
                                    } label: {
                                        Label("Use for signing", systemImage: "signature")
                                    }
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }

                GroupBox("Create a new signing key (ed25519)") {
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
                            if busy { ProgressView().controlSize(.small) } else { Text("Create GPG key") }
                        }
                        .disabled(busy || name.isEmpty || email.isEmpty || !gpg.available)
                    }
                    .padding(.top, 2)
                }

                if !exported.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Public key — paste into your Git host's GPG settings").font(.headline)
                            Spacer()
                            Button {
                                copyToClipboard(exported)
                                flash("Copied public key")
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                        MonospacedBox(text: exported).frame(height: 150)
                    }
                }

                if let message {
                    Text(message).font(.callout).foregroundStyle(isError ? .red : .green)
                }
            }
            .padding(24)
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
