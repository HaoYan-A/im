import Foundation

/// Keeps linked skills that have a source in step with upstream.
public struct SkillUpdater: Sendable {
    public enum Status: Sendable, Equatable {
        case upToDate
        /// Replaced with the newer upstream version just now.
        case updated
        /// Upstream has a newer version, but the im copy was edited, so it was left alone.
        case editedLocally
        /// The folder is gone from the source repository.
        case missingUpstream
        case failed(String)
    }

    public let environment: SkillEnvironment
    public let upstream: SkillUpstream

    public init(environment: SkillEnvironment, upstream: SkillUpstream) {
        self.environment = environment
        self.upstream = upstream
    }

    /// Checks every linked skill with a source and updates those not edited locally, plus those in `force`.
    /// Writes files and the manifest; the caller commits.
    public func run(only names: Set<String>? = nil, force: Set<String> = []) async -> [String: Status] {
        var manifest = SkillManifest.load(environment)
        let backup = SkillBackup(environment: environment)
        var heads: [String: GitTree] = [:]
        var statuses: [String: Status] = [:]

        for (name, entry) in manifest.skills.sorted(by: { $0.key < $1.key }) {
            guard let source = entry.source, names?.contains(name) ?? true else { continue }
            let local = environment.repositorySkill(name)
            guard FileManager.default.fileExists(atPath: local.path) else { continue }
            do {
                let head: GitTree
                if let cached = heads[source.repository] {
                    head = cached
                } else {
                    head = try await upstream.tree(source.repository, ref: "HEAD")
                    heads[source.repository] = head
                }
                guard let current = head.folder(source.path) else {
                    statuses[name] = .missingUpstream
                    continue
                }
                let localBlobs = SkillBlobs.of(local)
                if current.sha == source.treeSHA || localBlobs == current.blobs {
                    // Already current (perhaps updated by hand); just record it.
                    manifest.skills[name]?.source?.treeSHA = current.sha
                    statuses[name] = .upToDate
                    continue
                }
                let base = try await upstream.tree(source.repository, ref: source.treeSHA).blobs
                guard localBlobs == base || force.contains(name) else {
                    statuses[name] = .editedLocally
                    continue
                }
                try await replace(local, with: current.blobs, from: source.repository, backup: backup)
                manifest.skills[name]?.source?.treeSHA = current.sha
                statuses[name] = .updated
            } catch {
                statuses[name] = .failed(error.localizedDescription)
            }
        }
        if manifest != SkillManifest.load(environment) {
            try? manifest.save(environment)
        }
        return statuses
    }

    /// Follows `candidate` from now on. If the local files differ, they are replaced with the upstream
    /// version (the old copy goes to the backup), so updates can apply cleanly.
    public func adopt(_ name: String, candidate: SkillSourceFinder.Candidate) async throws {
        if !candidate.matchesLocal {
            try await replace(environment.repositorySkill(name), with: candidate.blobs, from: candidate.source.repository,
                              backup: SkillBackup(environment: environment))
        }
        var manifest = SkillManifest.load(environment)
        manifest.skills[name, default: .init(agents: SkillAgent.allCases)].source = candidate.source
        try manifest.save(environment)
    }

    /// Stops following upstream; the files stay as they are.
    public func stopTracking(_ name: String) throws {
        var manifest = SkillManifest.load(environment)
        manifest.skills[name]?.source = nil
        try manifest.save(environment)
    }

    /// Downloads into a staging folder first, so a failed download never leaves a half-updated skill.
    private func replace(_ folder: URL, with blobs: [String: String], from repository: String, backup: SkillBackup) async throws {
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent).staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        do {
            try await upstream.download(blobs, from: repository, to: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        try backup.move(folder)
        try FileManager.default.moveItem(at: staging, to: folder)
    }
}

/// Finds where a skill without a recorded source comes from on skills.sh.
public struct SkillSourceFinder: Sendable {
    public struct Candidate: Sendable, Identifiable, Hashable {
        public var id: String { "\(source.repository)/\(source.path)" }
        public let source: SkillSource
        public let installs: Int
        /// The upstream files are identical to the local copy.
        public let matchesLocal: Bool
        let blobs: [String: String]
    }

    public let upstream: SkillUpstream
    public let hub: SkillHubSearching

    public init(upstream: SkillUpstream, hub: SkillHubSearching) {
        self.upstream = upstream
        self.hub = hub
    }

    /// skills.sh skills with the same name, matching ones first, then by installs.
    public func candidates(for name: String, localFolder: URL, limit: Int = 4) async throws -> [Candidate] {
        let local = SkillBlobs.of(localFolder)
        let results = try await hub.search(name, limit: 30)
            .filter { $0.skillId == name && $0.isInstallable }
            .sorted { $0.installs > $1.installs }
            .prefix(limit)
        var candidates: [Candidate] = []
        for result in results {
            guard let head = try? await upstream.tree(result.source, ref: "HEAD"),
                  let path = head.skillFolders(named: name).first,
                  let folder = head.folder(path)
            else { continue }
            candidates.append(Candidate(
                source: SkillSource(repository: result.source, path: path, treeSHA: folder.sha),
                installs: result.installs,
                matchesLocal: folder.blobs == local,
                blobs: folder.blobs
            ))
        }
        return candidates.sorted { ($0.matchesLocal ? 1 : 0, $0.installs) > ($1.matchesLocal ? 1 : 0, $1.installs) }
    }
}

/// Installs a skill from skills.sh straight into im.
public struct SkillInstaller: Sendable {
    public let environment: SkillEnvironment
    public let upstream: SkillUpstream

    public init(environment: SkillEnvironment, upstream: SkillUpstream) {
        self.environment = environment
        self.upstream = upstream
    }

    /// Downloads `result` into `skills/<name>`, links it into `agents` and records its source. The caller commits.
    @discardableResult
    public func install(_ result: SkillHubResult, agents: Set<SkillAgent>) async throws -> SkillSource {
        let name = result.skillId
        guard result.isInstallable else { throw SkillError.notFoundUpstream(result.id) }
        guard !SkillScanner.scan(environment).contains(where: { $0.name == name }) else { throw SkillError.nameTaken(name) }

        let head = try await upstream.tree(result.source, ref: "HEAD")
        guard let path = head.skillFolders(named: name).first, let folder = head.folder(path) else {
            throw SkillError.notFoundUpstream(result.id)
        }
        let target = environment.repositorySkill(name)
        let staging = environment.repositorySkills.appendingPathComponent(".\(name).staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try await upstream.download(folder.blobs, from: result.source, to: staging)
        try FileManager.default.moveItem(at: staging, to: target)

        try SkillLinker(environment: environment).installLinks(name, into: agents)
        let source = SkillSource(repository: result.source, path: path, treeSHA: folder.sha)
        var manifest = SkillManifest.load(environment)
        manifest.skills[name] = .init(agents: agents.sorted(), source: source)
        try manifest.save(environment)
        return source
    }
}

/// The periodic job: sync with GitHub, pick up sources recorded by the skills CLI, apply upstream updates, push.
public enum SkillMaintenance {
    public struct Report: Sendable {
        public var statuses: [String: SkillUpdater.Status] = [:]
        public var syncError: String?

        public var updated: [String] { statuses.filter { $0.value == .updated }.map(\.key).sorted() }
        public var needingReview: [String] { statuses.filter { $0.value == .editedLocally }.map(\.key).sorted() }
    }

    public static func run(environment: SkillEnvironment, sync: RepoSync, upstream: SkillUpstream?) async -> Report {
        var report = Report()
        do {
            try sync.commitAndSync(["skills", ".im"], message: "chore(im): sync skills")
        } catch {
            report.syncError = error.localizedDescription
        }

        attachLockFileSources(environment)
        if let upstream {
            report.statuses = await SkillUpdater(environment: environment, upstream: upstream).run()
        }

        let updated = report.updated
        let message = updated.isEmpty ? "chore(im): track skill sources" : "chore(im): update skills from upstream: \(updated.joined(separator: ", "))"
        do {
            try sync.commitAndSync(["skills", ".im"], message: message)
        } catch {
            report.syncError = report.syncError ?? error.localizedDescription
        }
        return report
    }

    /// Linked skills installed with `npx skills` get the source recorded in its lock file.
    static func attachLockFileSources(_ environment: SkillEnvironment) {
        let lockSources = SkillSource.fromSkillsLockFile(home: environment.home)
        guard !lockSources.isEmpty else { return }
        var manifest = SkillManifest.load(environment)
        var changed = false
        for skill in SkillScanner.scan(environment) where skill.state == .linked {
            guard manifest.skills[skill.name]?.source == nil, let source = lockSources[skill.name] else { continue }
            manifest.skills[skill.name, default: .init(agents: skill.linkedAgents.sorted())].source = source
            changed = true
        }
        if changed { try? manifest.save(environment) }
    }
}
