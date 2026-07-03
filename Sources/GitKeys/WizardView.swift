import SwiftUI
import AppKit

struct WizardView: View {
    @EnvironmentObject var store: SSHConfigStore
    @EnvironmentObject var keyService: SSHKeyService

    @State private var host = "gitlab.spendee.com"
    @State private var user = "git"
    @State private var useExisting = true
    @State private var selectedKeyPath = ""
    @State private var newKeyName = "id_gitlab_spendee"
    @State private var newKeyComment = ""
    @State private var passphrase = ""

    @State private var busy = false
    @State private var status: String?
    @State private var statusError = false
    @State private var pubKeyToShow = ""
    @State private var testOutput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect a Git host").font(.largeTitle.bold())
                    Text("Set up SSH access to a self-hosted GitLab / GitHub / Gitea end-to-end.")
                        .foregroundStyle(.secondary)
                }

                step(1, "Where are you connecting?") {
                    LabeledContent("Host") {
                        TextField("gitlab.spendee.com", text: $host).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("SSH user") {
                        TextField("git", text: $user).textFieldStyle(.roundedBorder)
                    }
                }

                step(2, "Choose a key") {
                    Picker("Key source", selection: $useExisting) {
                        Text("Use an existing key").tag(true)
                        Text("Generate a new key").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if useExisting {
                        if keyService.keys.isEmpty {
                            Text("No keys found — switch to \"Generate a new key\".")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Key", selection: $selectedKeyPath) {
                                ForEach(keyService.keys) { key in
                                    Text("\(key.name)  (\(key.type))").tag(key.path)
                                }
                            }
                        }
                    } else {
                        LabeledContent("File name") {
                            TextField("id_gitlab_spendee", text: $newKeyName).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Comment") {
                            TextField("you@example.com", text: $newKeyComment).textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Passphrase") {
                            SecureField("optional", text: $passphrase).textFieldStyle(.roundedBorder)
                        }
                    }
                }

                step(3, "Write SSH config & reveal the public key") {
                    Button {
                        Task { await apply() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Set up key & config") }
                    }
                    .disabled(busy || host.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !pubKeyToShow.isEmpty {
                        HStack {
                            Text("Add this public key to your Git host").font(.headline)
                            Spacer()
                            Button {
                                copyToClipboard(pubKeyToShow)
                                status = "Public key copied to clipboard"
                                statusError = false
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Button { openKeysPage() } label: {
                                Label("Open host keys page", systemImage: "safari")
                            }
                        }
                        MonospacedBox(text: pubKeyToShow).frame(height: 80)
                    }
                }

                step(4, "Test the connection") {
                    Button {
                        Task { await test() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Test connection (ssh -T)") }
                    }
                    .disabled(busy || host.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !testOutput.isEmpty {
                        MonospacedBox(text: testOutput).frame(height: 80)
                    }
                    Text("Uses BatchMode, so it won't hang on a passphrase prompt. If your key has a passphrase, add it to the ssh-agent first.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let status {
                    Text(status).font(.callout).foregroundStyle(statusError ? .red : .green)
                }
            }
            .padding(24)
        }
        .onAppear {
            keyService.reload()
            if selectedKeyPath.isEmpty {
                let preferred = keyService.keys.first { $0.name == "id_ed25519" } ?? keyService.keys.first
                selectedKeyPath = preferred?.path ?? ""
            }
        }
    }

    // MARK: - Step chrome

    @ViewBuilder
    private func step<Content: View>(_ number: Int, _ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.headline)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor.opacity(0.2)))
                Text(title).font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(.leading, 36)
        }
    }

    // MARK: - Actions

    private func apply() async {
        busy = true
        status = nil
        statusError = false

        var identityFile = ""

        if useExisting {
            guard let key = keyService.keys.first(where: { $0.path == selectedKeyPath }) else {
                busy = false
                status = "Pick an existing key first."
                statusError = true
                return
            }
            identityFile = tildeify(key.path)
            pubKeyToShow = key.publicKey
        } else {
            let result = await keyService.generate(
                name: newKeyName, comment: newKeyComment, passphrase: passphrase
            )
            guard result.ok else {
                busy = false
                status = result.combinedOutput.isEmpty ? "Failed to create key." : result.combinedOutput
                statusError = true
                return
            }
            let trimmedName = newKeyName.trimmingCharacters(in: .whitespaces)
            if let key = keyService.keys.first(where: { $0.name == trimmedName }) {
                identityFile = tildeify(key.path)
                pubKeyToShow = key.publicKey
            }
        }

        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let cleanedUser = user.trimmingCharacters(in: .whitespaces).isEmpty ? "git" : user
        let newHost = SSHHost(patterns: cleanedHost, options: [
            SSHOption(keyword: "HostName", value: cleanedHost),
            SSHOption(keyword: "User", value: cleanedUser),
            SSHOption(keyword: "IdentityFile", value: identityFile),
            SSHOption(keyword: "IdentitiesOnly", value: "yes"),
            SSHOption(keyword: "PreferredAuthentications", value: "publickey")
        ])
        store.addOrReplaceHost(newHost)
        store.save()

        busy = false
        if let error = store.lastError {
            status = error
            statusError = true
        } else {
            let backup = store.lastSavedBackup ?? "n/a"
            status = "Config written (backup: \(backup)). Add the public key above to your host, then test."
            statusError = false
        }
    }

    private func test() async {
        busy = true
        testOutput = ""
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let cleanedUser = user.trimmingCharacters(in: .whitespaces).isEmpty ? "git" : user
        let target = "\(cleanedUser)@\(cleanedHost)"

        let result = await Task.detached {
            Shell.run("ssh", ["-T",
                              "-o", "StrictHostKeyChecking=accept-new",
                              "-o", "BatchMode=yes",
                              target])
        }.value
        busy = false

        testOutput = result.combinedOutput.isEmpty ? "exit code \(result.exitCode)" : result.combinedOutput
        if testOutput.lowercased().contains("welcome") {
            status = "🎉 Connected — the host recognised your key."
            statusError = false
        }
    }

    private func openKeysPage() {
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let urlString = "https://\(cleanedHost)/-/user_settings/ssh_keys"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
