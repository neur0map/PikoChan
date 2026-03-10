import Foundation

/// Persists cron jobs to `~/.pikochan/cron/jobs.json` with atomic writes.
/// Run records stored as JSONL in `~/.pikochan/cron/runs/<id>.jsonl`.
@MainActor
final class PikoCronStore {
    private let cronDir: URL
    private let runsDir: URL
    private let jobsFile: URL
    private let fm = FileManager.default

    private(set) var jobs: [PikoCronJob] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Max run records per job before pruning oldest.
    private static let maxRunRecords = 100

    init(cronDir: URL) {
        self.cronDir = cronDir
        self.runsDir = cronDir.appendingPathComponent("runs", isDirectory: true)
        self.jobsFile = cronDir.appendingPathComponent("jobs.json")
    }

    // MARK: - Load / Save

    func load() {
        try? fm.createDirectory(at: cronDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: runsDir, withIntermediateDirectories: true)

        guard fm.fileExists(atPath: jobsFile.path),
              let data = try? Data(contentsOf: jobsFile),
              let wrapper = try? decoder.decode(JobsWrapper.self, from: data)
        else {
            jobs = []
            return
        }
        jobs = wrapper.jobs
    }

    func save() {
        let wrapper = JobsWrapper(version: 1, jobs: jobs)
        guard let data = try? encoder.encode(wrapper) else { return }

        // Atomic write: write to .tmp then rename. Keep .bak for safety.
        let tmpFile = cronDir.appendingPathComponent("jobs.json.tmp")
        let bakFile = cronDir.appendingPathComponent("jobs.json.bak")

        do {
            try data.write(to: tmpFile, options: .atomic)
            // Set permissions: owner read/write only.
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpFile.path)

            if fm.fileExists(atPath: jobsFile.path) {
                // Backup existing.
                try? fm.removeItem(at: bakFile)
                try? fm.moveItem(at: jobsFile, to: bakFile)
            }
            try fm.moveItem(at: tmpFile, to: jobsFile)
        } catch {
            print("[PikoCronStore] Save failed: \(error)")
        }
    }

    // MARK: - CRUD

    func add(_ job: PikoCronJob) {
        jobs.append(job)
        save()
    }

    func remove(id: UUID) {
        jobs.removeAll { $0.id == id }
        // Clean up run records.
        let runFile = runsDir.appendingPathComponent("\(id.uuidString).jsonl")
        try? fm.removeItem(at: runFile)
        save()
    }

    func remove(name: String) {
        let matching = jobs.filter { $0.name.lowercased() == name.lowercased() }
        for job in matching {
            let runFile = runsDir.appendingPathComponent("\(job.id.uuidString).jsonl")
            try? fm.removeItem(at: runFile)
        }
        jobs.removeAll { $0.name.lowercased() == name.lowercased() }
        save()
    }

    func find(byName name: String) -> PikoCronJob? {
        jobs.first { $0.name.lowercased() == name.lowercased() }
    }

    func find(byID id: UUID) -> PikoCronJob? {
        jobs.first { $0.id == id }
    }

    /// Find by name or UUID string.
    func find(byNameOrID query: String) -> PikoCronJob? {
        if let uuid = UUID(uuidString: query), let job = find(byID: uuid) {
            return job
        }
        return find(byName: query)
    }

    func update(_ job: PikoCronJob) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
            save()
        }
    }

    // MARK: - Run Records

    func appendRunRecord(_ record: PikoCronRunRecord, forJob jobID: UUID) {
        let file = runsDir.appendingPathComponent("\(jobID.uuidString).jsonl")

        let recordEncoder = JSONEncoder()
        recordEncoder.dateEncodingStrategy = .iso8601
        recordEncoder.outputFormatting = []

        guard let data = try? recordEncoder.encode(record),
              let line = String(data: data, encoding: .utf8)
        else { return }

        if !fm.fileExists(atPath: file.path) {
            fm.createFile(atPath: file.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        handle.closeFile()

        pruneRunRecords(file: file)
    }

    func runRecords(forJob jobID: UUID) -> [PikoCronRunRecord] {
        let file = runsDir.appendingPathComponent("\(jobID.uuidString).jsonl")
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        let recordDecoder = JSONDecoder()
        recordDecoder.dateDecodingStrategy = .iso8601

        return contents.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? recordDecoder.decode(PikoCronRunRecord.self, from: data)
        }
    }

    func clearRunHistory(forJob jobID: UUID) {
        let file = runsDir.appendingPathComponent("\(jobID.uuidString).jsonl")
        try? fm.removeItem(at: file)
    }

    func clearAllRunHistory() {
        try? fm.removeItem(at: runsDir)
        try? fm.createDirectory(at: runsDir, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func pruneRunRecords(file: URL) {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return }
        let lines = contents.split(separator: "\n")
        guard lines.count > Self.maxRunRecords else { return }

        let kept = lines.suffix(Self.maxRunRecords).joined(separator: "\n") + "\n"
        try? kept.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Wrapper

    private struct JobsWrapper: Codable {
        let version: Int
        let jobs: [PikoCronJob]
    }
}
