import Foundation
import IMCore

/// The Skills window: what was found, what the user wants to change, and applying it.
@MainActor
final class SkillsViewModel: ObservableObject {
    /// The user's choice for one skill.
    struct Choice: Equatable {
        /// For skills not linked yet: link it when applying.
        var link = false
        var agents: Set<SkillAgent> = []
        var version: SkillVersion.ID?
        /// For linked skills: unlink it when applying.
        var unlink = false
    }

    enum Tab: Hashable { case installed, discover }

    @Published var tab = Tab.installed
    @Published private(set) var skills: [Skill] = []
    @Published var choices: [String: Choice] = [:]
    @Published private(set) var skipped: Set<String> = []
    @Published private(set) var isWorking = false
    @Published private(set) var hasScanned = false
    @Published private(set) var syncWarning: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var resultMessage: String?

    /// Agents and upstream sources of the skills in im.
    @Published private(set) var manifest = SkillManifest()
    /// Sources the skills CLI recorded for skills not in im yet; carried over when they are linked.
    @Published private(set) var lockSources: [String: SkillSource] = [:]
    @Published private(set) var updateStatuses: [String: SkillUpdater.Status] = [:]
    /// skills.sh matches for linked skills without a source, once the user asked to look.
    @Published private(set) var candidates: [String: [SkillSourceFinder.Candidate]] = [:]
    @Published private(set) var findingSource: Set<String> = []

    var close: () -> Void = {}

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var unlinked: [Skill] { skills.filter { $0.state != .linked } }
    var linked: [Skill] { skills.filter { $0.state == .linked } }

    /// Unlinked skills the user hasn't skipped; launch only opens the window for these.
    var pending: [Skill] { unlinked.filter { !skipped.contains($0.name) } }

    /// The primary button: what Apply will do, in words.
    var applyTitle: String {
        let changes = changes
        if !changes.isEmpty, changes.allSatisfy({ if case .link = $0.action { true } else { false } }) {
            return L("Link \(changes.count) Skills", "关联 \(changes.count) 个 Skill")
        }
        return changes.isEmpty ? L("Apply", "应用") : L("Apply \(changes.count) Changes", "应用 \(changes.count) 项更改")
    }

    var hasChanges: Bool { !changes.isEmpty }

    /// All, none or some of the unlinked skills are ticked.
    var selectionState: Bool? {
        let ticked = unlinked.filter { choices[$0.name]?.link == true }.count
        return ticked == 0 ? false : (ticked == unlinked.count ? true : nil)
    }

    func selectAll(_ selected: Bool) {
        for skill in unlinked {
            choices[skill.name]?.link = selected
        }
    }

    // MARK: Reload

    /// Syncs with GitHub and applies upstream updates, then scans. Sync problems (e.g. offline) don't stop the scan.
    func reload(sync shouldSync: Bool = true) async {
        guard let context = context() else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if shouldSync {
            let environment = context.environment
            let sync = context.sync()
            let upstream = context.upstream()
            let report = await Task.detached { await SkillMaintenance.run(environment: environment, sync: sync, upstream: upstream) }.value
            showReport(report)
        }
        await rescan()
    }

    /// Shows the outcome of a maintenance run, including ones started by the background timer.
    func showReport(_ report: SkillMaintenance.Report) {
        syncWarning = report.syncError.map { L("Could not sync with GitHub: \($0)", "无法与 GitHub 同步：\($0)") }
        updateStatuses = report.statuses
        let updated = report.updated
        if !updated.isEmpty {
            resultMessage = L("Updated from upstream: \(updated.joined(separator: ", ")).", "已从上游更新：\(updated.joined(separator: "、"))。")
        }
    }

    private func rescan() async {
        guard let environment = context()?.environment else { return }
        let scanned = await Task.detached { SkillScanner.scan(environment) }.value
        show(scanned, manifest: SkillManifest.load(environment))
    }

    private func show(_ scanned: [Skill], manifest: SkillManifest) {
        skipped = IMConfig.skippedSkills()
        self.manifest = manifest
        if let environment = context()?.environment {
            lockSources = SkillSource.fromSkillsLockFile(home: environment.home)
        }
        skills = scanned
        var choices: [String: Choice] = [:]
        for skill in scanned {
            switch skill.state {
            case .linked:
                choices[skill.name] = Choice(agents: skill.linkedAgents)
            case .notLinked, .onlyInIM:
                choices[skill.name] = Choice(link: !skipped.contains(skill.name), agents: manifest.agents(for: skill.name), version: skill.versions.first?.id)
            case .differentVersions:
                // Picking a version backs the other one up, so the user ticks these explicitly.
                choices[skill.name] = Choice(link: false, agents: manifest.agents(for: skill.name), version: skill.versions.first?.id)
            }
        }
        self.choices = choices
        hasScanned = true
    }

    // MARK: Apply

    private var changes: [SkillChange] {
        skills.compactMap { skill in
            guard let choice = choices[skill.name] else { return nil }
            switch skill.state {
            case .linked:
                if choice.unlink { return SkillChange(skill: skill, action: .unlink) }
                if choice.agents != skill.linkedAgents { return SkillChange(skill: skill, action: .setAgents(choice.agents)) }
                return nil
            case .notLinked, .differentVersions, .onlyInIM:
                guard choice.link, let version = choice.version, !choice.agents.isEmpty else { return nil }
                return SkillChange(skill: skill, action: .link(version: version, agents: choice.agents))
            }
        }
    }

    func apply() {
        guard let context = context() else { return }
        let changes = changes
        rememberSkipped()
        guard !changes.isEmpty else { return }

        isWorking = true
        appState.busy = true
        errorMessage = nil
        resultMessage = nil
        Task {
            defer {
                isWorking = false
                appState.busy = false
            }
            do {
                let names = changes.map(\.skill.name).joined(separator: ", ")
                let linker = SkillLinker(environment: context.environment)
                let sync = context.sync()
                try await Task.detached {
                    try linker.apply(changes)
                    try sync.commitAndSync(["skills", ".im"], message: "chore(im): update skills \(names)")
                }.value
                // Unlinking means "keep it out of im": don't tick it again or ask about it on launch.
                let unlinked = changes.compactMap { if case .unlink = $0.action { $0.skill.name } else { nil } }
                if !unlinked.isEmpty {
                    try IMConfig.setSkippedSkills(skipped.union(unlinked))
                }
                let allLinks = changes.allSatisfy { if case .link = $0.action { true } else { false } }
                resultMessage = allLinks
                    ? L("Linked \(changes.count) skills. Agents pick them up in new sessions.", "已关联 \(changes.count) 个 Skill，Agent 开新会话就能用。")
                    : L("Applied \(changes.count) changes. Agents pick them up in new sessions.", "已应用 \(changes.count) 项更改，Agent 开新会话就能用。")
            } catch {
                errorMessage = error.localizedDescription
            }
            await rescan()
        }
    }

    // MARK: Sources

    /// Looks for a linked skill on skills.sh by name and compares each match with the local files.
    func findSource(for skill: Skill) {
        guard let context = context(), let upstream = context.upstream() else { return }
        let folder = context.environment.repositorySkill(skill.name)
        findingSource.insert(skill.name)
        errorMessage = nil
        Task {
            defer { findingSource.remove(skill.name) }
            do {
                candidates[skill.name] = try await SkillSourceFinder(upstream: upstream, hub: SkillHub())
                    .candidates(for: skill.name, localFolder: folder)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Follows `candidate` for updates; a differing local copy is replaced (and backed up) first.
    func adopt(_ candidate: SkillSourceFinder.Candidate, for skill: Skill) {
        perform(message: "chore(im): track \(skill.name) from \(candidate.source.repository)") { context in
            guard let upstream = context.upstream() else { return [:] }
            try await SkillUpdater(environment: context.environment, upstream: upstream).adopt(skill.name, candidate: candidate)
            return [skill.name: .upToDate]
        }
        candidates[skill.name] = nil
    }

    /// Replaces a locally edited skill with the newer upstream version; the edited copy goes to the backup.
    func updateAnyway(_ skill: Skill) {
        perform(message: "chore(im): update \(skill.name) from upstream") { context in
            guard let upstream = context.upstream() else { return [:] }
            return await SkillUpdater(environment: context.environment, upstream: upstream).run(only: [skill.name], force: [skill.name])
        }
    }

    func stopTracking(_ skill: Skill) {
        perform(message: "chore(im): stop tracking \(skill.name) upstream") { context in
            try SkillUpdater(environment: context.environment, upstream: NoUpstream()).stopTracking(skill.name)
            return [:]
        }
        updateStatuses[skill.name] = nil
    }

    /// Runs `work`, records the update statuses it returns, then commits and pushes `skills/` and `.im/` and rescans.
    private func perform(message: String, _ work: @escaping @Sendable (Context) async throws -> [String: SkillUpdater.Status]) {
        guard let context = context() else { return }
        isWorking = true
        appState.busy = true
        errorMessage = nil
        Task {
            defer {
                isWorking = false
                appState.busy = false
            }
            do {
                updateStatuses.merge(try await work(context)) { $1 }
                let sync = context.sync()
                _ = try await Task.detached { try sync.commitAndSync(["skills", ".im"], message: message) }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            await rescan()
        }
    }

    /// Unlinked skills left unticked aren't offered on launch again; ticking one later un-skips it.
    func notNow() {
        rememberSkipped()
        close()
    }

    private func rememberSkipped() {
        var skipped = skipped
        for skill in unlinked {
            if choices[skill.name]?.link == true {
                skipped.remove(skill.name)
            } else {
                skipped.insert(skill.name)
            }
        }
        guard skipped != self.skipped else { return }
        do {
            try IMConfig.setSkippedSkills(skipped)
            self.skipped = skipped
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The skill folders, plus GitHub access built on demand so scanning alone never touches the Keychain.
    struct Context: Sendable {
        let environment: SkillEnvironment
        let sync: @Sendable () -> RepoSync
        /// nil without a token.
        let upstream: @Sendable () -> GitHubClient?
    }

    func context() -> Context? {
        guard let connection = appState.connection else { return nil }
        let owner = connection.fullName.split(separator: "/").first.map(String.init) ?? "im"
        let identity = connection.identity ?? GitIdentity(name: owner, email: "\(owner)@users.noreply.github.com")
        let environment = SkillEnvironment.live(repository: connection.localPath)
        return Context(
            environment: environment,
            sync: { RepoSync(repository: environment.repository, git: Git(token: TokenStore.load()), identity: identity) },
            upstream: { TokenStore.load().map { GitHubClient(token: $0) } }
        )
    }
}

/// For updater calls that never reach GitHub.
private struct NoUpstream: SkillUpstream {
    func tree(_ repository: String, ref: String) async throws -> GitTree { throw CancellationError() }
    func blob(_ repository: String, sha: String) async throws -> Data { throw CancellationError() }
}
