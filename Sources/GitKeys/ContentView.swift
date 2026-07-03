import SwiftUI

enum Panel: String, CaseIterable, Identifiable, Hashable {
    case wizard   = "Connect a Git host"
    case sshConfig = "SSH Config"
    case sshKeys  = "SSH Keys"
    case gpg      = "GPG & Signing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wizard:    return "wand.and.stars"
        case .sshConfig: return "doc.text"
        case .sshKeys:   return "key"
        case .gpg:       return "signature"
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
            List(selection: $selection) {
                ForEach(Panel.allCases) { panel in
                    Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                }
            }
            .frame(minWidth: 210)
            .navigationTitle("GitKeys")
        } detail: {
            Group {
                switch selection ?? .wizard {
                case .wizard:    WizardView()
                case .sshConfig: SSHConfigView()
                case .sshKeys:   SSHKeysView()
                case .gpg:       GPGView()
                }
            }
            .frame(minWidth: 560, minHeight: 520)
        }
        .environmentObject(configStore)
        .environmentObject(keyService)
        .environmentObject(gpgService)
    }
}
