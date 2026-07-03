import Foundation

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var ok: Bool { exitCode == 0 }

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Thin wrapper around `Process`. Runs everything through `/usr/bin/env` and
/// augments PATH so Homebrew tools (like `gpg`) are found even when the app is
/// launched from Finder with a minimal environment.
enum Shell {
    private static let extraPaths = [
        "/opt/homebrew/bin", "/usr/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ]

    @discardableResult
    static func run(_ command: String, _ args: [String] = [], input: String? = nil) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        var environment = ProcessInfo.processInfo.environment
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let merged = (extraPaths + existing).filter { seen.insert($0).inserted }
        environment["PATH"] = merged.joined(separator: ":")
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe  = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe
        if input != nil { process.standardInput = inPipe }

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "",
                                 stderr: "Failed to launch \(command): \(error.localizedDescription)")
        }

        if let input = input, let data = input.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
            try? inPipe.fileHandleForWriting.close()
        }

        // Read both pipes concurrently to avoid deadlocking on large output.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "gitkeys.shell.read", attributes: .concurrent)
        group.enter(); queue.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); queue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Returns the resolved path of a command, or nil if not on PATH.
    static func which(_ command: String) -> String? {
        let result = run("which", [command])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.ok && !path.isEmpty ? path : nil
    }
}
