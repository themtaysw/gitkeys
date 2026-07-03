import SwiftUI

enum Panel: String, CaseIterable, Identifiable, Hashable {
    case wizard   = "Connect a Git host"
    case doctor   = "Doctor"
    case sshConfig = "SSH Config"
    case sshKeys  = "SSH Keys"
    case gpg      = "GPG & Signing"
    case identities = "Identities"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wizard:    return "wand.and.stars"
        case .doctor:    return "stethoscope"
        case .sshConfig: return "doc.text"
        case .sshKeys:   return "key"
        case .gpg:       return "signature"
        case .identities: return "person.2"
        }
    }

    /// Distinct sidebar tile tint per panel.
    var tint: Color {
        switch self {
        case .wizard:    return GK.accentColor
        case .doctor:    return .green
        case .sshConfig: return .blue
        case .sshKeys:   return .teal
        case .gpg:       return .purple
        case .identities: return .orange
        }
    }
}

struct ContentView: View {
    @State private var selection: Panel? = .wizard

    @StateObject private var configStore = SSHConfigStore()
    @StateObject private var keyService  = SSHKeyService()
    @StateObject private var gpgService  = GPGService()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarAppHeader()

                List(selection: $selection) {
                    ForEach(Panel.allCases) { panel in
                        SidebarRow(panel: panel).tag(panel)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("GitKeys")
            .navigationSplitViewColumnWidth(min: 210, ideal: 236)
        } detail: {
            ZStack {
                DetailBackdrop()

                Group {
                    switch selection ?? .wizard {
                    case .wizard:    WizardView()
                    case .doctor:    DoctorView()
                    case .sshConfig: SSHConfigView()
                    case .sshKeys:   SSHKeysView()
                    case .gpg:       GPGView()
                    case .identities: IdentitiesView()
                    }
                }
            }
        }
        .environmentObject(configStore)
        .environmentObject(keyService)
        .environmentObject(gpgService)
        // Load everything AFTER first render. Blocking file/subprocess work inside a
        // @StateObject init runs during the SwiftUI render pass and crashes AttributeGraph,
        // so all initial loading happens here instead.
        .task {
            configStore.load()
            keyService.reload()
            await gpgService.reload()
        }
    }
}

// MARK: - Sidebar app header (decorative)

/// Gradient key badge + rounded wordmark shown above the sidebar list.
private struct SidebarAppHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GK.accentGradient)
                    .shadow(color: GK.accentColor.opacity(0.35), radius: 5, x: 0, y: 2)
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("GitKeys")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("SSH & GPG manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Sidebar row

/// Colored icon tile + panel name, System Settings style.
private struct SidebarRow: View {
    let panel: Panel

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: panel.icon, color: panel.tint)
            Text(panel.rawValue)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail backdrop

/// Full-bleed detail background: window background plus two very soft radial
/// accent glows (indigo top-leading, cyan bottom-trailing).
private struct DetailBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private var glowOpacity: Double { colorScheme == .dark ? 0.16 : 0.10 }

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.85

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                RadialGradient(
                    colors: [GK.accentColor.opacity(glowOpacity), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: radius
                )

                RadialGradient(
                    colors: [GK.accentCyan.opacity(glowOpacity), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: radius
                )
            }
        }
        .ignoresSafeArea()
    }
}
