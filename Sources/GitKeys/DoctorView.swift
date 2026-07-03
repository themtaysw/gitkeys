import SwiftUI

struct DoctorView: View {
    @StateObject private var doctor = DoctorService()

    @State private var message: String?
    @State private var isError = false
    @State private var fixingID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Title, run button and summary
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Doctor")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("One-click health checks for your SSH, agent and signing setup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 10) {
                        Button {
                            Task { await runAll() }
                        } label: {
                            GKBusyLabel(isBusy: doctor.isRunning) {
                                Label("Run checks", systemImage: "stethoscope")
                                    .frame(minWidth: 110)
                            }
                        }
                        .buttonStyle(.gkPrimary)
                        .disabled(doctor.isRunning || fixingID != nil)

                        if doctor.hasRun {
                            SummaryChip(
                                passed: doctor.passCount,
                                warnings: doctor.warnCount,
                                failed: doctor.failCount
                            )
                        }
                    }
                }

                // MARK: Check sections
                if doctor.checks.isEmpty {
                    VStack {
                        EmptyStateView(
                            icon: "stethoscope",
                            message: doctor.isRunning
                                ? "Examining your setup…"
                                : "Run checks to diagnose your SSH and signing setup."
                        )
                    }
                    .gkCard()
                } else {
                    ForEach(DoctorCheck.Category.allCases, id: \.self) { category in
                        let items = doctor.checks.filter { $0.category == category }
                        if !items.isEmpty {
                            categorySection(category, items)
                        }
                    }
                }

                if let message {
                    StatusBanner(text: message, isError: isError)
                }
            }
            .padding(GK.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(GK.spring, value: message)
            .animation(GK.spring, value: doctor.hasRun)
        }
        .task {
            if !doctor.hasRun {
                await runAll()
            }
        }
    }

    // MARK: - Sections

    private func categorySection(_ category: DoctorCheck.Category, _ items: [DoctorCheck]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                icon: category.gkIcon,
                title: category.rawValue,
                subtitle: category.gkSubtitle
            )

            VStack(spacing: 4) {
                ForEach(items) { check in
                    DoctorCheckRow(
                        check: check,
                        isFixing: fixingID == check.id,
                        fixDisabled: fixingID != nil || doctor.isRunning
                    ) {
                        Task { await fix(check) }
                    }
                }
            }
        }
        .gkCard()
    }

    // MARK: - Actions

    private func runAll() async {
        message = nil
        await doctor.runChecks()
    }

    private func fix(_ check: DoctorCheck) async {
        guard fixingID == nil else { return }
        fixingID = check.id
        let result = await doctor.fix(check)
        fixingID = nil
        let output = result.combinedOutput
        if result.ok {
            flash(output.isEmpty ? "Fixed: \(check.title)" : output)
        } else {
            flash(output.isEmpty ? "The fix for “\(check.title)” failed." : output, error: true)
        }
    }

    private func flash(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }
}

// MARK: - Category presentation

private extension DoctorCheck.Category {
    var gkIcon: String {
        switch self {
        case .sshFiles: return "folder.badge.gearshape"
        case .agent:    return "antenna.radiowaves.left.and.right"
        case .signing:  return "checkmark.seal.fill"
        }
    }

    var gkSubtitle: String {
        switch self {
        case .sshFiles: return "Permissions, stray files and config syntax in ~/.ssh"
        case .agent:    return "Which keys ssh-agent has loaded"
        case .signing:  return "GPG signing and Verified badges"
        }
    }
}

// MARK: - Status presentation

private extension DoctorCheck.Status {
    var gkIcon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    var gkColor: Color {
        switch self {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }
}

// MARK: - Summary chip

/// Compact "N passed · N warnings · N failed" capsule shown next to the title.
private struct SummaryChip: View {
    let passed: Int
    let warnings: Int
    let failed: Int

    var body: some View {
        HStack(spacing: 8) {
            stat(count: passed, word: "passed", color: .green)
            dot
            stat(count: warnings, word: warnings == 1 ? "warning" : "warnings", color: .orange)
            dot
            stat(count: failed, word: "failed", color: .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var dot: some View {
        Text("·")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
    }

    private func stat(count: Int, word: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(count) \(word)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Check row

/// One diagnostic result: status icon, title + multiline detail, and a Fix
/// button when the check is fixable and not passing. Highlights on hover.
private struct DoctorCheckRow: View {
    let check: DoctorCheck
    let isFixing: Bool
    let fixDisabled: Bool
    let onFix: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.status.gkIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(check.status.gkColor)
                .frame(width: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if let fixLabel = check.fixLabel, check.status != .pass {
                Button {
                    onFix()
                } label: {
                    ZStack {
                        Text(fixLabel).opacity(isFixing ? 0 : 1)
                        if isFixing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.gkSecondary)
                .disabled(fixDisabled)
            }
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
