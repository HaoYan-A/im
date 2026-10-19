import Foundation

/// What to do with one skill.
public struct SkillChange: Sendable {
    public enum Action: Sendable {
        /// Put this version into im and link it into the given agents.
        case link(version: SkillVersion.ID, agents: Set<SkillAgent>)
        /// Change which agents a linked skill is installed in.
        case setAgents(Set<SkillAgent>)
        /// Replace the links with real folders again; the im copy stays.
        case unlink
    }

    public let skill: Skill
    public let action: Action

    public init(skill: Skill, action: Action) {
        self.skill = skill
        self.action = action
    }
}

public enum SkillError: LocalizedError {
    case versionNotFound(String)
    case occupied(URL)

    public var errorDescription: String? {
        switch self {
        case let .versionNotFound(name):
            L("The chosen version of \(name) no longer exists. Reload and try again.",
              "\(name) 选中的版本已经不存在了，请重新加载后再试。")
        case let .occupied(url):
            L("\(url.path) already exists and is not a link, so im left it alone.",
              "\(url.path) 已经存在且不是软链接，im 没有动它。")
        }
    }
}

/// Which agents each skill in im is installed in, stored in the repository so every machine agrees.
public struct SkillManifest: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var agents: [SkillAgent]
    }

    public var skills: [String: Entry] = [:]

    static func url(_ environment: SkillEnvironment) -> URL {
        environment.repository.appendingPathComponent(".im/skills.json")
    }

    public static func load(_ environment: SkillEnvironment) -> SkillManifest {
        guard let data = try? Data(contentsOf: url(environment)) else { return SkillManifest() }
        return (try? JSONDecoder().decode(SkillManifest.self, from: data)) ?? SkillManifest()
    }

    func save(_ environment: SkillEnvironment) throws {
        let url = Self.url(environment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(self) + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    /// Agents to install a skill into; every agent unless the user narrowed it down.
    public func agents(for name: String) -> Set<SkillAgent> {
        skills[name].map { Set($0.agents) } ?? Set(SkillAgent.allCases)
    }
}

/// Links skills into im and back. Never deletes user files: replaced folders go to the backup folder.
public struct SkillLinker: Sendable {
    public let environment: SkillEnvironment
    private let backup: URL

    public init(environment: SkillEnvironment, now: Date = Date()) {
        self.environment = environment
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        backup = environment.backups.appendingPathComponent(stamp, isDirectory: true)
    }

    public func apply(_ changes: [SkillChange]) throws {
        var manifest = SkillManifest.load(environment)
        for change in changes {
            switch change.action {
            case let .link(version, agents):
                try link(change.skill, version: version, agents: agents)
                manifest.skills[change.skill.name] = .init(agents: agents.sorted())
            case let .setAgents(agents):
                try setAgents(change.skill, agents)
                manifest.skills[change.skill.name] = .init(agents: agents.sorted())
            case .unlink:
                try unlink(change.skill)
            }
        }
        if manifest != SkillManifest.load(environment) {
            try manifest.save(environment)
        }
    }

    /// Turns every linked skill back into real folders, so the agents keep working when this
    /// repository's clone goes away (disconnecting, switching repositories).
    /// - Returns: How many skills were unlinked.
    @discardableResult
    public func unlinkAll() throws -> Int {
        let linked = SkillScanner.scan(environment).filter { !$0.linkedAgents.isEmpty }
        try apply(linked.map { SkillChange(skill: $0, action: .unlink) })
        return linked.count
    }

    private func link(_ skill: Skill, version id: SkillVersion.ID, agents: Set<SkillAgent>) throws {
        guard let version = skill.versions.first(where: { $0.id == id }) else {
            throw SkillError.versionNotFound(skill.name)
        }
        let fm = FileManager.default
        let target = environment.repositorySkill(skill.name)

        if !version.copies.contains(where: { $0.agent == nil }) {
            // Copy before moving anything: the chosen folder may be one of the copies backed up below.
            let staging = environment.repositorySkills.appendingPathComponent(".\(skill.name).staging", isDirectory: true)
            try? fm.removeItem(at: staging)
            try Self.copyTree(from: version.source, to: staging)
            if fm.fileExists(atPath: target.path) {
                try moveToBackup(target)
            }
            try fm.moveItem(at: staging, to: target)
        }

        for copy in skill.agentCopies {
            if copy.isSymlink {
                // Only the link goes; whatever it points at is either backed up as its own copy or not ours.
                try fm.removeItem(at: copy.location)
            } else {
                try moveToBackup(copy.location)
            }
        }
        try install(skill.name, into: agents)
    }

    private func setAgents(_ skill: Skill, _ agents: Set<SkillAgent>) throws {
        for agent in skill.linkedAgents.subtracting(agents) {
            try removeLink(skill.name, from: agent)
        }
        try install(skill.name, into: agents.subtracting(skill.linkedAgents))
    }

    private func unlink(_ skill: Skill) throws {
        for copy in skill.agentCopies where copy.isLinkedToIM {
            try FileManager.default.removeItem(at: copy.location)
            try Self.copyTree(from: environment.repositorySkill(skill.name), to: copy.location)
        }
    }

    private func install(_ name: String, into agents: Set<SkillAgent>) throws {
        let fm = FileManager.default
        for agent in agents.sorted() {
            let directory = agent.installDirectory(home: environment.home)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let link = directory.appendingPathComponent(name)
            if Self.isSymlink(link) {
                try fm.removeItem(at: link)
            } else if fm.fileExists(atPath: link.path) {
                throw SkillError.occupied(link)
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: environment.repositorySkill(name))
        }
    }

    private func removeLink(_ name: String, from agent: SkillAgent) throws {
        let link = agent.installDirectory(home: environment.home).appendingPathComponent(name)
        if Self.isSymlink(link) {
            try FileManager.default.removeItem(at: link)
        }
    }

    /// Moves a folder into this run's backup, mirroring its path under the home folder.
    private func moveToBackup(_ url: URL) throws {
        let fm = FileManager.default
        // Compare resolved paths: the same folder may be reached as /var/… and /private/var/….
        let home = environment.home.resolvingSymlinksInPath().path + "/"
        let path = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        let relative = path.hasPrefix(home) ? String(path.dropFirst(home.count)) : url.lastPathComponent
        var destination = backup.appendingPathComponent(relative)
        var attempt = 1
        while fm.fileExists(atPath: destination.path) {
            attempt += 1
            destination = backup.appendingPathComponent("\(relative)-\(attempt)")
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: url, to: destination)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// Copies a folder, keeping symlinks as links and leaving out `.git` and `.DS_Store`.
    static func copyTree(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        where !SkillScanner.ignoredNames.contains(item.lastPathComponent) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if !isSymlink(item), (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try copyTree(from: item, to: target)
            } else {
                try fm.copyItem(at: item, to: target)
            }
        }
    }
}
