import Foundation

enum Shell {
    /// Runs an executable and returns stdout, or nil on failure. Kills the
    /// process if it exceeds `timeout` seconds.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        // Discard stderr instead of piping it — an undrained pipe can fill up
        // and deadlock the child process.
        process.standardError = FileHandle.nullDevice

        let label = (path as NSString).lastPathComponent
        let start = Date()

        do {
            try process.run()
        } catch {
            Log.shell.error("\(label, privacy: .public) failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)

        // .uncaughtSignal means we killed it (terminate/SIGKILL above) rather
        // than it exiting on its own — i.e. it hit the timeout.
        if process.terminationReason == .uncaughtSignal {
            Log.shell.warning("\(label, privacy: .public) timed out after \(elapsed, format: .fixed(precision: 1))s and was killed")
        }
        guard process.terminationStatus == 0 else {
            Log.shell.debug("\(label, privacy: .public) exited \(process.terminationStatus) after \(elapsed, format: .fixed(precision: 2))s")
            return nil
        }
        if elapsed > 2 {
            Log.shell.debug("\(label, privacy: .public) took \(elapsed, format: .fixed(precision: 2))s")
        }
        return data
    }

    static func runString(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
        guard let data = run(path, arguments, timeout: timeout),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Locates a command in the usual Homebrew / local install directories.
    static func findTool(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
