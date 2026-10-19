import Foundation

/// An agent whose personal skills im can manage.
public enum SkillAgent: String, CaseIterable, Codable, Sendable, Comparable {
    case claudeCode = "claude-code"
    /// Codex CLI and the Codex desktop app, which share their skill folders.
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Where im puts the link for a linked skill.
    public func installDirectory(home: URL) -> URL {
        switch self {
        case .claudeCode: home.appendingPathComponent(".claude/skills", isDirectory: true)
        case .codex: home.appendingPathComponent(".agents/skills", isDirectory: true)
        }
    }

    /// Every user-level folder the agent reads skills from, install directory first.
    public func scanDirectories(home: URL) -> [URL] {
        switch self {
        case .claudeCode: [installDirectory(home: home)]
        // ~/.codex/skills is the legacy location Codex still reads (and its skill installer writes to).
        case .codex: [installDirectory(home: home), home.appendingPathComponent(".codex/skills", isDirectory: true)]
        }
    }

    public static func < (lhs: SkillAgent, rhs: SkillAgent) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// The folders skills management works with. Tests point these at temporary directories.
public struct SkillEnvironment: Sendable {
    public var home: URL
    /// Root of the memory repository clone.
    public var repository: URL
    public var backups: URL

    public init(home: URL, repository: URL, backups: URL) {
        self.home = home
        self.repository = repository
        self.backups = backups
    }

    public static func live(repository: URL) -> SkillEnvironment {
        var home = FileManager.default.homeDirectoryForCurrentUser
        var repository = repository
        #if DEBUG
        // Lets design review render the Skills window against fixture folders.
        let overrides = ProcessInfo.processInfo.environment
        if let path = overrides["IM_DEBUG_HOME"] { home = URL(fileURLWithPath: path) }
        if let path = overrides["IM_DEBUG_REPO"] { repository = URL(fileURLWithPath: path) }
        #endif
        return SkillEnvironment(
            home: home,
            repository: repository,
            backups: IMPaths.home.appendingPathComponent("backup/skills", isDirectory: true)
        )
    }

    public var repositorySkills: URL { repository.appendingPathComponent("skills", isDirectory: true) }

    public func repositorySkill(_ name: String) -> URL {
        repositorySkills.appendingPathComponent(name, isDirectory: true)
    }
}

/// One place a skill was found: an agent's skills folder or the im repository.
public struct SkillCopy: Sendable, Hashable {
    /// nil for the copy in the im repository.
    public let agent: SkillAgent?
    /// The entry in the skills folder; may be a symlink.
    public let location: URL
    /// The real folder holding the files.
    public let source: URL
    public let isSymlink: Bool
    /// True when this agent copy is a link into the im repository.
    public let isLinkedToIM: Bool
    public let content: SkillContent
}

/// What a skill folder contains, for comparing copies.
public struct SkillContent: Sendable, Hashable {
    /// Relative path → SHA-256 of the file.
    public let files: [String: String]
    public let modified: Date

    /// Identical for folders with identical files.
    public var fingerprint: String {
        files.keys.sorted().map { "\($0)\u{0}\(files[$0]!)" }.joined(separator: "\n").sha256
    }
}

/// One distinct content among a skill's copies.
public struct SkillVersion: Sendable, Identifiable, Hashable {
    public var id: String { content.fingerprint }
    public let content: SkillContent
    /// Copies with this content; the first is used as the source when linking.
    public let copies: [SkillCopy]

    public var source: URL { copies[0].source }
    /// Where this version is found, e.g. [Claude Code] or [im].
    public var owners: [SkillAgent?] {
        var seen: [SkillAgent?] = []
        for copy in copies where !seen.contains(copy.agent) { seen.append(copy.agent) }
        return seen
    }
}

/// All copies of one skill, grouped by folder name.
public struct Skill: Sendable, Identifiable, Hashable {
    public enum State: Sendable {
        /// Every agent copy links into the im repository.
        case linked
        /// Found in agents, not in im yet, all copies identical.
        case notLinked
        /// Copies differ; the user must pick a version.
        case differentVersions
        /// In the im repository but not installed on this machine.
        case onlyInIM
    }

    public var id: String { name }
    public let name: String
    public let description: String?
    public let repositoryCopy: SkillCopy?
    public let agentCopies: [SkillCopy]

    public var state: State {
        if agentCopies.isEmpty { return .onlyInIM }
        if repositoryCopy != nil, agentCopies.allSatisfy(\.isLinkedToIM) { return .linked }
        return versions.count > 1 ? .differentVersions : .notLinked
    }

    /// Agents that currently have this skill, linked or not.
    public var installedAgents: Set<SkillAgent> { Set(agentCopies.compactMap(\.agent)) }

    /// Agents linked to the im copy.
    public var linkedAgents: Set<SkillAgent> { Set(agentCopies.filter(\.isLinkedToIM).compactMap(\.agent)) }

    /// Distinct contents, newest first. Links into im count as the im copy.
    public var versions: [SkillVersion] {
        var copiesByFingerprint: [String: [SkillCopy]] = [:]
        var order: [String] = []
        for copy in [repositoryCopy].compactMap({ $0 }) + agentCopies.filter({ !$0.isLinkedToIM }) {
            let key = copy.content.fingerprint
            if copiesByFingerprint[key] == nil { order.append(key) }
            copiesByFingerprint[key, default: []].append(copy)
        }
        return order
            .map { SkillVersion(content: copiesByFingerprint[$0]![0].content, copies: copiesByFingerprint[$0]!) }
            .sorted { $0.content.modified > $1.content.modified }
    }

    /// Files whose content differs between versions.
    public var differingFiles: [String] {
        let versions = versions
        let paths = Set(versions.flatMap(\.content.files.keys))
        return paths.filter { path in Set(versions.map { $0.content.files[path] }).count > 1 }.sorted()
    }
}
