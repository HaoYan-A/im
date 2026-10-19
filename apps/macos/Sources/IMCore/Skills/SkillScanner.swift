import CryptoKit
import Foundation

/// Finds every personal skill of the supported agents plus the ones in the im repository.
public enum SkillScanner {
    /// Folder entries that never belong to a skill's content.
    static let ignoredNames: Set<String> = [".git", ".DS_Store"]

    public static func scan(_ environment: SkillEnvironment) -> [Skill] {
        let repositoryRoot = environment.repositorySkills.resolvingSymlinksInPath()
        var repositoryCopies: [String: SkillCopy] = [:]
        for (name, entry) in skillFolders(in: environment.repositorySkills) {
            repositoryCopies[name] = copy(agent: nil, location: entry, repositoryRoot: repositoryRoot)
        }

        var agentCopies: [String: [SkillCopy]] = [:]
        for agent in SkillAgent.allCases {
            for directory in agent.scanDirectories(home: environment.home) {
                for (name, entry) in skillFolders(in: directory) {
                    agentCopies[name, default: []].append(copy(agent: agent, location: entry, repositoryRoot: repositoryRoot))
                }
            }
        }

        return Set(repositoryCopies.keys).union(agentCopies.keys).sorted().map { name in
            let copies = agentCopies[name] ?? []
            let any = repositoryCopies[name] ?? copies[0]
            return Skill(
                name: name,
                description: description(of: any.source),
                repositoryCopy: repositoryCopies[name],
                agentCopies: copies
            )
        }
    }

    /// Visible subfolders (or symlinks to folders) that contain a SKILL.md, by name.
    private static func skillFolders(in directory: URL) -> [(String, URL)] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
            .map { ($0.lastPathComponent, $0) }
    }

    private static func copy(agent: SkillAgent?, location: URL, repositoryRoot: URL) -> SkillCopy {
        let isSymlink = (try? location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        let source = location.resolvingSymlinksInPath()
        return SkillCopy(
            agent: agent,
            location: location,
            source: source,
            isSymlink: isSymlink,
            isLinkedToIM: agent != nil && isSymlink && source.deletingLastPathComponent().path == repositoryRoot.path,
            content: content(of: source)
        )
    }

    static func content(of folder: URL) -> SkillContent {
        var files: [String: String] = [:]
        var modified = Date.distantPast
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
        let base = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        while let url = enumerator?.nextObject() as? URL {
            if ignoredNames.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let data = try? Data(contentsOf: url)
            else { continue }
            let path = url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
            files[path] = data.sha256
            modified = max(modified, values.contentModificationDate ?? .distantPast)
        }
        return SkillContent(files: files, modified: modified)
    }

    /// The `description:` from SKILL.md's front matter.
    static func description(of folder: URL) -> String? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard line.hasPrefix("description:") else { continue }
            var value = line.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty || value == ">" || value == "|" ? nil : value
        }
        return nil
    }
}

extension Data {
    var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

extension String {
    var sha256: String { Data(utf8).sha256 }
}
