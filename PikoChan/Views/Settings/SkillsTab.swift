import SwiftUI

struct SkillsTab: View {
    @State private var config = PikoConfigStore.shared
    @State private var skillLoader = PikoSkillLoader.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Permissions

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Allow terminal commands", isOn: $config.skillsTerminalEnabled)
                        Toggle("Allow browser opening", isOn: $config.skillsBrowserEnabled)
                        Toggle("Auto-execute safe commands", isOn: $config.skillsAutoExecuteSafe)

                        Text("Safe commands (ls, cat, git status, etc.) run automatically. Others require confirmation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Loaded Skills

                GroupBox("Loaded Skills") {
                    if skillLoader.loadedSkills.isEmpty {
                        Text("No skills found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(skillLoader.loadedSkills.enumerated()), id: \.element.id) { index, skill in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(skill.name)
                                                .font(.system(size: 13, weight: .medium))
                                            if skill.isBuiltIn {
                                                Text("Built-in")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(.secondary.opacity(0.15))
                                                    )
                                            }
                                        }
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { skillLoader.loadedSkills[index].enabled },
                                        set: { skillLoader.loadedSkills[index].enabled = $0 }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Actions

                HStack(spacing: 12) {
                    Button("Reload Skills") {
                        skillLoader.reload()
                    }

                    Button("Open Skills Folder") {
                        let url = PikoHome().skillsDir
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .onChange(of: config.skillsTerminalEnabled) { try? config.save() }
        .onChange(of: config.skillsBrowserEnabled) { try? config.save() }
        .onChange(of: config.skillsAutoExecuteSafe) { try? config.save() }
        .onAppear {
            skillLoader.reload()
        }
    }
}
