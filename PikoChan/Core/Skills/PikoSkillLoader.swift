import Foundation

struct PikoSkill: Identifiable {
    let id: String           // filename sans .md
    let name: String         // frontmatter "name:"
    let description: String  // frontmatter "description:"
    let permissions: [String]
    let instructions: String // body after frontmatter
    let isBuiltIn: Bool
    var enabled: Bool = true
}

@Observable
@MainActor
final class PikoSkillLoader {
    static let shared = PikoSkillLoader()

    var loadedSkills: [PikoSkill] = []

    private let home = PikoHome()

    func reload() {
        var skills: [PikoSkill] = []

        // Built-in skills from ~/.pikochan/skills/
        skills.append(contentsOf: scanDirectory(home.skillsDir, builtIn: true))
        // Custom skills from ~/.pikochan/skills/custom/
        skills.append(contentsOf: scanDirectory(home.customSkillsDir, builtIn: false))
        // MCP auto-generated skills from ~/.pikochan/mcp/skills/
        skills.append(contentsOf: scanDirectory(home.mcpSkillsDir, builtIn: false))

        loadedSkills = skills
        PikoGateway.shared.logSkillsReload(count: skills.count)
    }

    func buildPromptBlock() -> String {
        let enabled = loadedSkills.filter(\.enabled)
        guard !enabled.isEmpty else { return "" }

        var lines = ["<available_skills>"]
        for skill in enabled {
            lines.append("<skill name=\"\(skill.name)\">")
            let body = skill.instructions.count > 1000
                ? String(skill.instructions.prefix(1000)) + "..."
                : skill.instructions
            lines.append(body)
            lines.append("</skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func scanDirectory(_ dir: URL, builtIn: Bool) -> [PikoSkill] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { parseSkillFile($0, builtIn: builtIn) }
    }

    private func parseSkillFile(_ file: URL, builtIn: Bool) -> PikoSkill? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        let id = file.deletingPathExtension().lastPathComponent

        // Parse YAML frontmatter between --- delimiters.
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else {
            // No frontmatter — use filename as name, full text as instructions.
            return PikoSkill(id: id, name: id, description: "", permissions: [],
                             instructions: text.trimmingCharacters(in: .whitespacesAndNewlines),
                             isBuiltIn: builtIn)
        }

        let frontmatter = parts[1]
        let body = parts.dropFirst(2).joined(separator: "---")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let map = parseSimpleYAML(frontmatter)
        let name = map["name"] ?? id
        let description = map["description"] ?? map["trigger"] ?? ""
        let permissions = map["permissions"]?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            ?? parseYAMLList(frontmatter, key: "permissions")

        return PikoSkill(id: id, name: name, description: description,
                         permissions: permissions, instructions: body,
                         isBuiltIn: builtIn)
    }

    private func parseSimpleYAML(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("-") { continue }
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            map[key] = value
        }
        return map
    }

    private func parseYAMLList(_ text: String, key: String) -> [String] {
        var result: [String] = []
        var inKey = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\(key):") {
                inKey = true
                continue
            }
            if inKey {
                if line.hasPrefix("- ") {
                    var item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if (item.hasPrefix("\"") && item.hasSuffix("\"")) ||
                       (item.hasPrefix("'") && item.hasSuffix("'")) {
                        item = String(item.dropFirst().dropLast())
                    }
                    result.append(item)
                } else {
                    inKey = false
                }
            }
        }
        return result
    }
}
