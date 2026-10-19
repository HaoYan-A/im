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

    @Published private(set) var skills: [Skill] = []
    @Published var choices: [String: Choice] = [:]
    @Published private(set) var skipped: Set<String> = []
    @Published private(set) var isWorking = false
    @Published private(set) var hasScanned = false
    @Published private(set) var syncWarning: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var resultMessage: String?

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

    /// Syncs linked skills with GitHub, then scans. Sync problems (e.g. offline) don't stop the scan.
    func reload(sync shouldSync: Bool = true) async {
        guard let context = context() else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if shouldSync {
            let sync = context.sync()
            let warning: String? = await Task.detached {
                do {
                    try sync.commitAndSync(["skills", ".im"], message: "chore(im): sync skills")
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            syncWarning = warning.map { L("Could not sync with GitHub: \($0)", "无法与 GitHub 同步：\($0)") }
        }

        let environment = context.environment
        let scanned = await Task.detached { SkillScanner.scan(environment) }.value
        show(scanned, manifest: SkillManifest.load(environment))
    }

    private func show(_ scanned: [Skill], manifest: SkillManifest) {
        skipped = IMConfig.skippedSkills()
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
                let allLinks = changes.allSatisfy { if case .link = $0.action { true } else { false } }
                resultMessage = allLinks
                    ? L("Linked \(changes.count) skills. Agents pick them up in new sessions.", "已关联 \(changes.count) 个 Skill，Agent 开新会话就能用。")
                    : L("Applied \(changes.count) changes. Agents pick them up in new sessions.", "已应用 \(changes.count) 项更改，Agent 开新会话就能用。")
            } catch {
                errorMessage = error.localizedDescription
            }
            let environment = context.environment
            show(await Task.detached { SkillScanner.scan(environment) }.value, manifest: SkillManifest.load(environment))
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

    /// The skill folders, plus git access built on demand so scanning alone never touches the Keychain.
    private func context() -> (environment: SkillEnvironment, sync: () -> RepoSync)? {
        guard let connection = appState.connection else { return nil }
        let owner = connection.fullName.split(separator: "/").first.map(String.init) ?? "im"
        let identity = connection.identity ?? GitIdentity(name: owner, email: "\(owner)@users.noreply.github.com")
        return (
            SkillEnvironment.live(repository: connection.localPath),
            { RepoSync(repository: connection.localPath, git: Git(token: TokenStore.load()), identity: identity) }
        )
    }
}
