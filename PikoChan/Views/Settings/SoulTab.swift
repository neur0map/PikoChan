import SwiftUI

/// Settings tab for personality editing and memory management.
struct SoulTab: View {
    @State private var soul: PikoSoul = .default
    @State private var rulesText: String = ""
    @State private var status: String = ""
    @State private var statusColor: Color = .secondary
    @State private var showClearConfirmation = false

    @State private var memoryCount: Int = 0
    @State private var conversationCount: Int = 0

    private let home = PikoHome()
    private let communicationStyles = ["casual", "formal", "playful", "snarky"]

    @State private var logEntryCount: Int = 0
    @State private var logFileCount: Int = 0

    var body: some View {
        Form {
            personalitySection
            moodSection
            memorySection
            logsSection
            setupSection
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 580)
        .onAppear { load() }
    }

    // MARK: - Personality

    @ViewBuilder
    private var personalitySection: some View {
        Section("Personality") {
            TextField("Name:", text: $soul.name)
            TextField("Tagline:", text: $soul.tagline)

            Picker("Style:", selection: $soul.communicationStyle) {
                ForEach(communicationStyles, id: \.self) { style in
                    Text(style.capitalized).tag(style)
                }
            }

            Stepper("Sass level: \(soul.sassLevel)", value: $soul.sassLevel, in: 1...5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Rules (one per line):")
                    .font(.callout)
                TextEditor(text: $rulesText)
                    .font(.body.monospaced())
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Save") { save() }
                Button("Open personality.yaml") { openFile(home.personalityFile) }
                Spacer()
                if !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(statusColor)
                }
            }
        }
    }

    // MARK: - Mood

    @ViewBuilder
    private var moodSection: some View {
        Section("Current Mood") {
            HStack {
                Image("pikochan_sprite")
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("Mood resets to neutral after 5 minutes of inactivity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Memory

    @ViewBuilder
    private var memorySection: some View {
        Section("Memory") {
            LabeledContent("Memories stored:") {
                Text("\(memoryCount)")
                    .monospacedDigit()
            }
            LabeledContent("Conversations recorded:") {
                Text("\(conversationCount)")
                    .monospacedDigit()
            }

            HStack {
                Button("Open Journal") { openFile(home.journalFile) }
                Button("Clear All Memory") { showClearConfirmation = true }
                    .foregroundStyle(.red)
            }
        }
        .alert("Clear All Memory?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearMemory() }
        } message: {
            Text("This will delete all conversation history and memories. This cannot be undone.")
        }
    }

    // MARK: - Logs

    @ViewBuilder
    private var logsSection: some View {
        Section("Gateway Logs") {
            LabeledContent("Today's events:") {
                Text("\(logEntryCount)")
                    .monospacedDigit()
            }
            LabeledContent("Log files:") {
                Text("\(logFileCount)")
                    .monospacedDigit()
            }

            HStack {
                Button("Open Today's Log") {
                    if let file = PikoGateway.shared.todayLogFile {
                        NSWorkspace.shared.open(file)
                    }
                }
                Button("Open Logs Folder") {
                    openFile(home.logsDir)
                }
            }

            Text("Logs track every message, response, mood change, memory operation, and error as structured JSONL.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Setup

    @ViewBuilder
    private var setupSection: some View {
        Section("Setup Wizard") {
            Button("Re-run Setup Wizard") {
                // Close settings window first, then trigger setup.
                NSApp.keyWindow?.close()
                NotificationCenter.default.post(name: .pikoRerunSetup, object: nil)
            }

            Text("Re-runs the first-time setup to reconfigure your AI provider and re-index memories.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func load() {
        soul = PikoSoul.load(from: home.personalityFile)
        rulesText = soul.rules.joined(separator: "\n")
        refreshStats()
    }

    private func save() {
        soul.rules = rulesText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        do {
            try soul.save(to: home.personalityFile)
            showStatus("Saved", color: .green)
        } catch {
            showStatus("Save failed", color: .red)
        }
    }

    private func clearMemory() {
        let store = PikoStore(path: home.memoryDBFile)
        store?.clearAll()
        // Clear journal file.
        try? "# PikoChan Journal\n\n".write(to: home.journalFile, atomically: true, encoding: .utf8)
        refreshStats()
        showStatus("Memory cleared", color: .orange)
    }

    private func refreshStats() {
        let store = PikoStore(path: home.memoryDBFile)
        memoryCount = store?.memoryCount() ?? 0
        conversationCount = store?.turnCount() ?? 0
        logEntryCount = PikoGateway.shared.todayEntryCount()
        logFileCount = PikoGateway.shared.allLogFiles().count
    }

    private func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func showStatus(_ text: String, color: Color) {
        status = text
        statusColor = color
        Task {
            try? await Task.sleep(for: .seconds(3))
            if status == text { status = "" }
        }
    }
}
