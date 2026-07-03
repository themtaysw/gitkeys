import SwiftUI

struct SSHConfigView: View {
    @EnvironmentObject var store: SSHConfigStore

    @State private var selectedID: SSHHost.ID?
    @State private var message: String?
    @State private var isError = false
    @State private var hoveredID: SSHHost.ID?

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return store.hosts.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                hostList

                if let idx = selectedIndex {
                    hostEditor(idx)
                } else {
                    EmptyStateView(
                        icon: "square.and.pencil",
                        message: "Select a host to edit, or add a new one."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let message {
                StatusBanner(text: message, isError: isError)
            }
        }
        .padding(GK.pagePadding)
        .animation(GK.spring, value: message)
        .animation(GK.spring, value: selectedID)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SSH Config")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Edit host aliases and connection options")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { addHost() } label: { Label("Add host", systemImage: "plus") }
                        .buttonStyle(.gkSecondary)
                    Button { store.load(); flash("Reloaded from disk") } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.gkSecondary)
                    Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.gkPrimary)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.configURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Host list

    @ViewBuilder
    private var hostList: some View {
        Group {
            if store.hosts.isEmpty {
                EmptyStateView(icon: "server.rack", message: "No hosts yet.\nAdd one to get started.")
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(store.hosts) { host in
                        HostRowLabel(host: host)
                            .tag(host.id)
                            .listRowBackground(rowBackground(host))
                            .onHover { inside in
                                if inside {
                                    hoveredID = host.id
                                } else if hoveredID == host.id {
                                    hoveredID = nil
                                }
                            }
                    }
                    .onDelete { store.hosts.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 230)
        .frame(minHeight: 320)
        .gkCard(padding: 6)
    }

    @ViewBuilder
    private func rowBackground(_ host: SSHHost) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if selectedID == host.id {
                shape
                    .fill(GK.accentGradient)
                    .opacity(0.16)
                    .overlay(shape.strokeBorder(GK.accentColor.opacity(0.35), lineWidth: 1))
            } else if hoveredID == host.id {
                shape.fill(Color.primary.opacity(0.06))
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .animation(.easeOut(duration: 0.15), value: hoveredID)
    }

    // MARK: - Editor

    @ViewBuilder
    private func hostEditor(_ idx: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    icon: "network",
                    title: "Host entry",
                    subtitle: "Patterns and options written to ssh_config"
                )

                LabeledContent("Host") {
                    TextField("pattern(s)", text: $store.hosts[idx].patterns)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                Divider()

                ForEach($store.hosts[idx].options) { $opt in
                    if opt.isRaw {
                        Text(opt.keyword.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "(blank line)" : opt.keyword)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    } else {
                        HStack(spacing: 10) {
                            TextField("Keyword", text: $opt.keyword)
                                .textFieldStyle(.roundedBorder).frame(width: 180)
                            TextField("Value", text: $opt.value)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                removeOption(idx, opt.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.red)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .help("Remove option")
                            .accessibilityLabel("Remove option")
                        }
                    }
                }

                HStack {
                    Button {
                        store.hosts[idx].options.append(SSHOption(keyword: "", value: ""))
                    } label: {
                        Label("Add option", systemImage: "plus")
                    }
                    .buttonStyle(.gkSecondary)
                    Spacer()
                    Button(role: .destructive) { deleteHost(idx) } label: {
                        Label("Delete host", systemImage: "trash")
                    }
                    .buttonStyle(.gkDestructive)
                }
                .padding(.top, 6)
            }
            .padding(2)
        }
        .gkCard(padding: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Host row

private struct HostRowLabel: View {
    let host: SSHHost

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: "server.rack", color: GK.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(host.hostName.isEmpty ? "—" : host.hostName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
