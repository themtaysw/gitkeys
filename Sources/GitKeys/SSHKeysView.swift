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
            VStack(alignment: .leading, spacing: 18) {
                Text("SSH Keys").font(.largeTitle.bold())

                GroupBox("Existing keys in ~/.ssh") {
                    if keyService.keys.isEmpty {
                        Text("No SSH keys found.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(keyService.keys) { key in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key.name).font(.headline)
                                        Text(key.comment.isEmpty ? key.type : "\(key.type) · \(key.comment)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        copyToClipboard(key.publicKey)
                                        flash("Copied public key for \(key.name)")
                                    } label: {
                                        Label("Copy public key", systemImage: "doc.on.doc")
                                    }
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }

                GroupBox("Generate a new ed25519 key") {
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
                        HStack(spacing: 10) {
                            Button {
                                Task { await generate() }
                            } label: {
                                if busy { ProgressView().controlSize(.small) } else { Text("Generate key") }
                            }
                            .disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            Text("Saves to ~/.ssh/\(newName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }

                if let message {
                    Text(message).font(.callout).foregroundStyle(isError ? .red : .green)
                }
            }
            .padding(24)
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
