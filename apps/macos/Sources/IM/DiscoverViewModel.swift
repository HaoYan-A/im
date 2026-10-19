import Foundation
import IMCore

/// The Discover tab: search skills.sh, preview a skill from GitHub, install it into im.
@MainActor
final class DiscoverViewModel: ObservableObject {
    struct Preview: Equatable {
        /// SKILL.md without its front matter.
        let body: String
        let files: [String]
    }

    enum InstallState: Equatable {
        case available
        /// Installed into im from this very source.
        case installed
        /// Some other skill already uses the name.
        case nameTaken
        /// A well-known (non-GitHub) source im can't install from.
        case unsupported
    }

    @Published var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var results: [SkillHubResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published var selection: SkillHubResult.ID? {
        didSet { if selection != oldValue { loadPreview() } }
    }
    @Published private(set) var previews: [SkillHubResult.ID: Preview] = [:]
    @Published private(set) var loadingPreview: SkillHubResult.ID?
    @Published var agents = Set(SkillAgent.allCases)
    @Published private(set) var installing: SkillHubResult.ID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var message: String?

    private let skills: SkillsViewModel
    private let appState: AppState
    private var searchTask: Task<Void, Never>?

    init(skills: SkillsViewModel, appState: AppState) {
        self.skills = skills
        self.appState = appState
    }

    var selected: SkillHubResult? { results.first { $0.id == selection } }

    func installState(of result: SkillHubResult) -> InstallState {
        guard result.isInstallable else { return .unsupported }
        if skills.manifest.skills[result.skillId]?.source?.repository == result.source { return .installed }
        if skills.skills.contains(where: { $0.name == result.skillId }) { return .nameTaken }
        return .available
    }

    // MARK: Search

    /// Waits for typing to pause before asking skills.sh.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            results = []
            hasSearched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let found = try await SkillHub().search(query, limit: 40)
                guard !Task.isCancelled else { return }
                results = found
                hasSearched = true
                errorMessage = nil
                if selection == nil || !found.contains(where: { $0.id == selection }) {
                    selection = found.first?.id
                }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: Preview

    private func loadPreview() {
        guard let result = selected, result.isInstallable, previews[result.id] == nil,
              let upstream = skills.context()?.upstream()
        else { return }
        loadingPreview = result.id
        Task {
            defer { if loadingPreview == result.id { loadingPreview = nil } }
            do {
                let head = try await upstream.tree(result.source, ref: "HEAD")
                guard let path = head.skillFolders(named: result.skillId).first, let folder = head.folder(path),
                      let sha = folder.blobs["SKILL.md"]
                else { throw SkillError.notFoundUpstream(result.id) }
                let text = String(decoding: try await upstream.blob(result.source, sha: sha), as: UTF8.self)
                previews[result.id] = Preview(body: Self.stripFrontMatter(text), files: folder.blobs.keys.sorted())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func stripFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let lines = text.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return text }
        return lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Install

    func install(_ result: SkillHubResult) {
        guard let context = skills.context(), let upstream = context.upstream(), !agents.isEmpty else { return }
        let agents = agents
        installing = result.id
        appState.busy = true
        errorMessage = nil
        message = nil
        Task {
            defer {
                installing = nil
                appState.busy = false
            }
            do {
                try await SkillInstaller(environment: context.environment, upstream: upstream).install(result, agents: agents)
                let sync = context.sync()
                _ = try await Task.detached {
                    try sync.commitAndSync(["skills", ".im"], message: "chore(im): install \(result.skillId) from \(result.source)")
                }.value
                message = L("Installed \(result.skillId). im keeps it up to date; agents pick it up in new sessions.",
                            "已安装 \(result.skillId)。im 会自动保持更新，Agent 开新会话就能用。")
            } catch {
                errorMessage = error.localizedDescription
            }
            await skills.reload(sync: false)
        }
    }
}
