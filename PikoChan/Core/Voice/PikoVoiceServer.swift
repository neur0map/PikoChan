import Foundation
import Observation

@Observable
@MainActor
final class PikoVoiceServer {

    enum Status: Equatable {
        case stopped
        case starting
        case running
        case errored(String)

        var label: String {
            switch self {
            case .stopped:         "Stopped"
            case .starting:        "Starting..."
            case .running:         "Running"
            case .errored(let msg): "Error: \(msg)"
            }
        }
    }

    static let shared = PikoVoiceServer()

    var status: Status = .stopped
    var modelName: String = ""
    var availableVoices: [String] = []

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var retryCount = 0
    private var pollTask: Task<Void, Never>?
    /// Incremented on each start/stop to invalidate stale termination handlers.
    private var generation = 0
    private static let maxRetries = 3
    private static let defaultPort = 7879

    private init() {}

    // MARK: - Start / Stop

    func start(modelPath: String, port: Int = 7879) {
        guard status != .starting && status != .running else { return }
        guard !modelPath.isEmpty else {
            status = .errored("No model path configured")
            return
        }
        guard Self.pythonAvailable() else {
            status = .errored("python3 not found")
            return
        }

        let home = PikoHome()
        // Ensure voice dirs + server.py exist.
        try? home.bootstrap()
        let serverScript = home.voiceServerFile.path

        guard FileManager.default.fileExists(atPath: serverScript) else {
            status = .errored("server.py not found")
            return
        }

        // Kill any orphaned server from a previous session still holding the port.
        Self.killProcessOnPort(port)

        status = .starting
        generation += 1
        let currentGeneration = generation
        modelName = URL(fileURLWithPath: modelPath).lastPathComponent

        PikoGateway.shared.logVoiceServerStart(model: modelName, port: port)

        let proc = Process()
        // Prefer the venv python if it exists, otherwise fall back to system python3.
        let venvPython = home.voiceDir.appendingPathComponent("venv/bin/python3").path
        if FileManager.default.fileExists(atPath: venvPython) {
            proc.executableURL = URL(fileURLWithPath: venvPython)
            proc.arguments = [serverScript, "--model", modelPath, "--port", String(port)]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["python3", serverScript, "--model", modelPath, "--port", String(port)]
        }
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        // Use the user's login-shell PATH so python3/pip packages are found.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.userShellPATH
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        stdoutPipe = stdout
        stderrPipe = stderr

        // Accumulate stderr so we can show a useful error on crash.
        let stderrBuffer = StderrBuffer()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                PikoGateway.shared.logError(message: "voice-server stdout: \(trimmed)", subsystem: .voice)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            stderrBuffer.append(line)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                PikoGateway.shared.logError(message: "voice-server stderr: \(trimmed)", subsystem: .voice)
            }
        }

        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore stale handlers from previous start/stop cycles.
                guard self.generation == currentGeneration else { return }

                self.pollTask?.cancel()
                self.pollTask = nil
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil

                if self.status == .running || self.status == .starting {
                    let stderrText = stderrBuffer.text
                    let reason: String
                    let isDependencyError = stderrText.contains("ModuleNotFoundError") || stderrText.contains("Missing dependency")
                    let isPortConflict = stderrText.contains("address already in use")

                    if isDependencyError {
                        // Extract the missing module name for a clear error.
                        if let match = stderrText.range(of: "No module named '([^']+)'", options: .regularExpression) {
                            reason = "Missing Python package: \(stderrText[match].replacingOccurrences(of: "No module named '", with: "").replacingOccurrences(of: "'", with: ""))"
                        } else {
                            reason = "Missing Python dependencies"
                        }
                    } else if isPortConflict {
                        reason = "Port \(port) already in use"
                    } else {
                        reason = "Exit code \(proc.terminationStatus)"
                    }

                    PikoGateway.shared.logVoiceServerCrash(reason: reason, retryCount: self.retryCount)

                    // Don't retry on dependency or port errors — retrying won't help.
                    if !isDependencyError && !isPortConflict && self.retryCount < Self.maxRetries {
                        self.retryCount += 1
                        self.status = .stopped
                        self.start(modelPath: modelPath, port: port)
                    } else {
                        self.status = .errored(reason)
                    }
                }
            }
        }

        do {
            try proc.run()
            process = proc
            pollUntilReady(port: port, expectedGeneration: currentGeneration)
        } catch {
            status = .errored(error.localizedDescription)
        }
    }

    func stop() {
        generation += 1 // Invalidate any pending termination handlers.
        pollTask?.cancel()
        pollTask = nil

        guard let proc = process, proc.isRunning else {
            status = .stopped
            process = nil
            return
        }

        proc.terminate() // SIGTERM
        // Give it 3 seconds, then SIGKILL.
        Task {
            try? await Task.sleep(for: .seconds(3))
            if proc.isRunning {
                proc.interrupt() // SIGINT as stronger hint
                try? await Task.sleep(for: .seconds(1))
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        status = .stopped
        retryCount = 0
    }

    func restart(modelPath: String, port: Int = 7879) {
        stop()
        Task {
            try? await Task.sleep(for: .seconds(1))
            self.start(modelPath: modelPath, port: port)
        }
    }

    // MARK: - Health / Voices

    func healthCheck() async -> (ok: Bool, model: String, device: String) {
        guard let url = URL(string: "http://127.0.0.1:\(7879)/health") else {
            return (false, "", "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "ok"
        else {
            return (false, "", "")
        }
        return (true, json["model"] as? String ?? "", json["device"] as? String ?? "")
    }

    func fetchVoices() async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:\(7879)/voices") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voices = json["voices"] as? [String]
        else { return [] }
        return voices
    }

    // MARK: - Polling

    private func pollUntilReady(port: Int, expectedGeneration: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // Wait 10s before first poll — model loading takes 30s+ on CPU.
            try? await Task.sleep(for: .seconds(10))

            // Then poll /health every 5 seconds for up to ~100 seconds.
            for _ in 0..<18 {
                guard !Task.isCancelled else { return }
                guard let self, self.generation == expectedGeneration else { return }

                // Stop polling immediately if the process has died.
                if let proc = self.process, !proc.isRunning {
                    // terminationHandler will handle restart/error.
                    return
                }

                let result = await self.healthCheck()
                if result.ok {
                    self.status = .running
                    self.availableVoices = await self.fetchVoices()
                    PikoGateway.shared.logVoiceServerReady(model: result.model, device: result.device)
                    return
                }

                try? await Task.sleep(for: .seconds(5))
            }
            // Timed out.
            guard let self, self.generation == expectedGeneration else { return }
            if self.status == .starting {
                self.status = .errored("Server didn't respond within 100s")
            }
        }
    }

    // MARK: - Static Utilities

    /// Resolve the user's full login-shell PATH.
    /// Foundation.Process inherits a minimal PATH that misses ~/.local/bin, brew paths, etc.
    private static let userShellPATH: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-ilc", "echo $PATH"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
    }()

    /// Run `which <cmd>` using the user's login-shell PATH.
    private static func commandExists(_ command: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]
        proc.environment = ["PATH": userShellPATH]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }

    /// Kill any process listening on the given port and wait for it to be released.
    nonisolated private static func killProcessOnPort(_ port: Int) {
        // Find PIDs using the port.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        proc.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        var pids: [Int32] = []
        do {
            try proc.run()
            proc.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
               let output = String(data: data, encoding: .utf8) {
                pids = output.split(separator: "\n").compactMap {
                    Int32($0.trimmingCharacters(in: .whitespaces))
                }
            }
        } catch {}

        guard !pids.isEmpty else { return }

        // SIGTERM first for clean socket shutdown, then SIGKILL after 1s.
        for pid in pids { kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 1.0)
        for pid in pids { kill(pid, SIGKILL) }

        // Wait up to 3s for port to be released.
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            if !isPortInUse(port) { return }
        }
    }

    /// Quick check if a TCP port is in use.
    nonisolated private static func isPortInUse(_ port: Int) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        proc.arguments = ["-ti", ":\(port)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }

    static func pythonAvailable() -> Bool {
        commandExists("python3")
    }

    static func soxAvailable() -> Bool {
        commandExists("sox")
    }

    static func huggingfaceCLIAvailable() -> Bool {
        // pipx installs as "hf", pip installs as "huggingface-cli".
        commandExists("hf") || commandExists("huggingface-cli")
    }

    /// Check if required Python packages are importable (prefers venv).
    static func pythonDepsAvailable() -> Bool {
        let home = PikoHome()
        let venvPython = home.voiceDir.appendingPathComponent("venv/bin/python3").path

        let proc = Process()
        if FileManager.default.fileExists(atPath: venvPython) {
            proc.executableURL = URL(fileURLWithPath: venvPython)
            proc.arguments = ["-c", "import fastapi, uvicorn, torch, qwen_tts, soundfile"]
        } else {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            proc.executableURL = URL(fileURLWithPath: shell)
            proc.arguments = ["-ilc", "python3 -c 'import fastapi, uvicorn, torch, qwen_tts, soundfile'"]
        }
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }

    /// Whether the PikoChan venv exists at ~/.pikochan/voice/venv.
    static func venvExists() -> Bool {
        let home = PikoHome()
        return FileManager.default.fileExists(
            atPath: home.voiceDir.appendingPathComponent("venv/bin/python3").path
        )
    }

    struct InstalledModel: Identifiable {
        let name: String
        let path: String
        let sizeBytes: UInt64
        var id: String { path }

        var sizeLabel: String {
            let gb = Double(sizeBytes) / 1_073_741_824
            if gb >= 1.0 {
                return String(format: "%.1f GB", gb)
            }
            let mb = Double(sizeBytes) / 1_048_576
            return String(format: "%.0f MB", mb)
        }
    }

    static func installedModels() -> [InstalledModel] {
        let home = PikoHome()
        let modelsDir = home.voiceModelsDir
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let size = Self.directorySize(url, fm: fm)
            return InstalledModel(name: url.lastPathComponent, path: url.path, sizeBytes: size)
        }
    }

    private static func directorySize(_ url: URL, fm: FileManager) -> UInt64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += UInt64(size)
            }
        }
        return total
    }
}

// MARK: - Stderr Buffer (thread-safe)

private final class StderrBuffer: Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        // Keep last 50 lines to avoid unbounded growth.
        _lines.append(line)
        if _lines.count > 50 { _lines.removeFirst() }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return _lines.joined()
    }
}
