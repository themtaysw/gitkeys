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

    @State private var applyBusy = false
    @State private var testBusy = false
    @State private var uploadBusy = false
    @State private var status: String?
    @State private var statusError = false
    @State private var pubKeyToShow = ""
    @State private var testOutput = ""

    // Step 4 — key upload. The token lives only in this field and the macOS
    // Keychain; it is never logged or written anywhere else.
    @State private var token = ""
    @State private var rememberToken = true
    @State private var uploadSucceeded = false

    private var anyBusy: Bool { applyBusy || testBusy || uploadBusy }

    private var connectionSucceeded: Bool {
        testOutput.lowercased().contains("welcome")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect a Git host")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Set up SSH access to a self-hosted GitLab / GitHub / Gitea end-to-end.")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                stepCard(1, "Where are you connecting?",
                         done: !host.trimmingCharacters(in: .whitespaces).isEmpty) {
                    LabeledContent("Host") {
                        TextField("gitlab.spendee.com", text: $host).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("SSH user") {
                        TextField("git", text: $user).textFieldStyle(.roundedBorder)
                    }
                }

                stepCard(2, "Choose a key") {
                    Picker("Key source", selection: $useExisting) {
                        Text("Use an existing key").tag(true)
                        Text("Generate a new key").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if useExisting {
                        if keyService.keys.isEmpty {
                            EmptyStateView(
                                icon: "key.slash",
                                message: "No keys found — switch to \"Generate a new key\"."
                            )
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

                stepCard(3, "Write SSH config & reveal the public key",
                         done: !pubKeyToShow.isEmpty) {
                    Button {
                        Task { await apply() }
                    } label: {
                        GKBusyLabel(isBusy: applyBusy) {
                            Text("Set up key & config")
                        }
                    }
                    .buttonStyle(.gkPrimary)
                    .disabled(anyBusy || host.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !pubKeyToShow.isEmpty {
                        HStack {
                            Text("Add this public key to your Git host")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Spacer()
                            Button {
                                copyToClipboard(pubKeyToShow)
                                status = "Public key copied to clipboard"
                                statusError = false
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.gkSecondary)
                            Button { openKeysPage() } label: {
                                Label("Open host keys page", systemImage: "safari")
                            }
                            .buttonStyle(.gkSecondary)
                        }
                        MonospacedBox(text: pubKeyToShow).frame(height: 80)
                    }
                }

                stepCard(4, "Upload the key to your host (optional)", done: uploadSucceeded) {
                    LabeledContent("Access token") {
                        SecureField("Personal access token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Remember in Keychain", isOn: $rememberToken)

                    Button {
                        Task { await upload() }
                    } label: {
                        GKBusyLabel(isBusy: uploadBusy) {
                            Text("Upload public key")
                        }
                    }
                    .buttonStyle(.gkPrimary)
                    .disabled(anyBusy
                              || pubKeyToShow.isEmpty
                              || token.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text(tokenCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                stepCard(5, "Test the connection", done: connectionSucceeded) {
                    Button {
                        Task { await test() }
                    } label: {
                        GKBusyLabel(isBusy: testBusy) {
                            Text("Test connection (ssh -T)")
                        }
                    }
                    .buttonStyle(.gkPrimary)
                    .disabled(anyBusy || host.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !testOutput.isEmpty {
                        MonospacedBox(text: testOutput).frame(height: 80)
                    }
                    Text("Uses BatchMode, so it won't hang on a passphrase prompt. If your key has a passphrase, add it to the ssh-agent first.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let status {
                    statusBanner(for: status)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(GK.pagePadding)
            .animation(GK.spring, value: status)
            .animation(GK.spring, value: statusError)
            .animation(GK.spring, value: pubKeyToShow)
            .animation(GK.spring, value: testOutput)
            .animation(GK.spring, value: useExisting)
            .animation(GK.spring, value: uploadSucceeded)
        }
        .onAppear {
            keyService.reload()
            if selectedKeyPath.isEmpty {
                let preferred = keyService.keys.first { $0.name == "id_ed25519" } ?? keyService.keys.first
                selectedKeyPath = preferred?.path ?? ""
            }
            prefillTokenFromKeychain()
        }
    }

    // MARK: - Token helpers

    private var tokenCaption: String {
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let hostLabel = cleanedHost.isEmpty ? "your GitLab host" : cleanedHost
        let create: String
        switch HostKind.detect(from: cleanedHost) {
        case .github:
            create = "Create a token on GitHub under Settings > Developer settings > Personal access tokens, with the admin:public_key scope."
        case .gitlab:
            create = "Create a token on \(hostLabel) under Preferences > Access Tokens, with the api scope."
        }
        return create + " The token is stored only in the macOS Keychain."
    }

    /// Prefills the token field from the Keychain (off the main thread).
    private func prefillTokenFromKeychain() {
        guard token.isEmpty else { return }
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        guard !cleanedHost.isEmpty else { return }
        Task {
            let stored = await Task.detached { TokenStore.load(host: cleanedHost) }.value
            if let stored, !stored.isEmpty, token.isEmpty {
                token = stored
            }
        }
    }

    // MARK: - Step chrome

    @ViewBuilder
    private func stepCard<Content: View>(_ number: Int, _ title: String,
                                         done: Bool = false,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StepBadge(number: number, done: done)
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 12) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gkCard(padding: 18)
    }

    // MARK: - Status banner

    @ViewBuilder
    private func statusBanner(for message: String) -> some View {
        // Celebratory styling for the success moment (the 🎉 message set by test()).
        if !statusError && message.contains("🎉") {
            StatusBanner(text: message, isError: false)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(GK.accentGradient, lineWidth: 1.5)
                )
                .shadow(color: GK.accentCyan.opacity(0.35), radius: 12, x: 0, y: 4)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            StatusBanner(text: message, isError: statusError)
        }
    }

    // MARK: - Actions

    private func apply() async {
        applyBusy = true
        status = nil
        statusError = false

        var identityFile = ""

        if useExisting {
            guard let key = keyService.keys.first(where: { $0.path == selectedKeyPath }) else {
                applyBusy = false
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
                applyBusy = false
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

        applyBusy = false
        if let error = store.lastError {
            status = error
            statusError = true
        } else {
            let backup = store.lastSavedBackup ?? "n/a"
            status = "Config written (backup: \(backup)). Add the public key above to your host, then test."
            statusError = false
        }
    }

    private func upload() async {
        uploadBusy = true
        status = nil
        statusError = false

        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let tokenValue = token
        let remember = rememberToken
        let publicKey = pubKeyToShow

        // Comment is the third field of the public-key line, when present.
        let parts = publicKey.split(separator: " ", maxSplits: 2).map(String.init)
        let comment = parts.count > 2 ? parts[2] : ""

        // Keychain access and the computer-name lookup stay off the main thread.
        let title = await Task.detached { () -> String in
            if remember {
                TokenStore.save(host: cleanedHost, token: tokenValue)
            } else {
                TokenStore.delete(host: cleanedHost)
            }
            return HostAPIClient.defaultTitle(keyComment: comment)
        }.value

        let result = await HostAPIClient.uploadKey(
            host: cleanedHost, token: tokenValue, title: title, publicKey: publicKey
        )

        uploadBusy = false
        status = result.message
        statusError = !result.ok
        if result.ok {
            uploadSucceeded = true
        }
    }

    private func test() async {
        testBusy = true
        testOutput = ""
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedUser = user.trimmingCharacters(in: .whitespaces)
        let cleanedUser = trimmedUser.isEmpty ? "git" : trimmedUser

        // A leading "-" would let ssh parse the destination as an option
        // (e.g. -oProxyCommand=… runs an arbitrary command) — reject it and
        // terminate option parsing with "--" before the destination.
        guard !cleanedUser.hasPrefix("-"), !cleanedHost.hasPrefix("-") else {
            testBusy = false
            status = "The SSH user and host must not start with “-”."
            statusError = true
            return
        }
        let target = "\(cleanedUser)@\(cleanedHost)"

        let result = await Task.detached {
            Shell.run("ssh", ["-T",
                              "-o", "StrictHostKeyChecking=accept-new",
                              "-o", "BatchMode=yes",
                              "--",
                              target])
        }.value
        testBusy = false

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
