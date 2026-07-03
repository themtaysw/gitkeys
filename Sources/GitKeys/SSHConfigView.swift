import SwiftUI

struct SSHConfigView: View {
    @EnvironmentObject var store: SSHConfigStore

    @State private var selectedID: SSHHost.ID?
    @State private var message: String?
    @State private var isError = false

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return store.hosts.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH Config").font(.largeTitle.bold())
                Spacer()
                Button { addHost() } label: { Label("Add host", systemImage: "plus") }
                Button { store.load(); flash("Reloaded from disk") } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
            }
            Text(store.configURL.path).font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                List(selection: $selectedID) {
                    ForEach(store.hosts) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.displayName).font(.headline)
                            Text(host.hostName.isEmpty ? "—" : host.hostName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(host.id)
                    }
                    .onDelete { store.hosts.remove(atOffsets: $0) }
                }
                .frame(width: 230)
                .frame(minHeight: 320)

                if let idx = selectedIndex {
                    hostEditor(idx)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a host to edit, or add a new one.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(isError ? .red : .green)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func hostEditor(_ idx: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Host") {
                    TextField("pattern(s)", text: $store.hosts[idx].patterns)
                        .textFieldStyle(.roundedBorder)
                }
                Divider()

                ForEach($store.hosts[idx].options) { $opt in
                    if opt.isRaw {
                        Text(opt.keyword.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "(blank line)" : opt.keyword)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 8) {
                            TextField("Keyword", text: $opt.keyword)
                                .textFieldStyle(.roundedBorder).frame(width: 180)
                            TextField("Value", text: $opt.value)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                removeOption(idx, opt.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    Button {
                        store.hosts[idx].options.append(SSHOption(keyword: "", value: ""))
                    } label: {
                        Label("Add option", systemImage: "plus")
                    }
                    Spacer()
                    Button(role: .destructive) { deleteHost(idx) } label: {
                        Label("Delete host", systemImage: "trash")
                    }
                }
                .padding(.top, 4)
            }
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func addHost() {
        let host = SSHHost(patterns: "new-host", options: [
            SSHOption(keyword: "HostName", value: ""),
            SSHOption(keyword: "User", value: "git"),
            SSHOption(keyword: "IdentityFile", value: "~/.ssh/id_ed25519")
        ])
        store.hosts.append(host)
        selectedID = host.id
    }

    private func removeOption(_ idx: Int, _ optID: SSHOption.ID) {
        store.hosts[idx].options.removeAll { $0.id == optID }
    }

    private func deleteHost(_ idx: Int) {
        let removedID = store.hosts[idx].id
        store.hosts.remove(at: idx)
        if selectedID == removedID { selectedID = nil }
    }

    private func save() {
        store.save()
        if let error = store.lastError {
            flash(error, error: true)
        } else if let backup = store.lastSavedBackup {
            flash("Saved. Backup: \(backup)")
        } else {
            flash("Saved.")
        }
    }

    private func flash(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }
}
