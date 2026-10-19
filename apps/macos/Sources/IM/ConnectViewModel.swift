import Foundation
import IMCore

/// First-run flow: sign in to GitHub, pick or create a private repository, initialize it.
@MainActor
final class ConnectViewModel: ObservableObject {
    enum Step { case signIn, chooseRepository, working, done }
    enum Mode: Hashable { case create, existing }

    @Published var step: Step = .signIn
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Sign in
    @Published var tokenInput = ""
    @Published private(set) var cliToken: String?
    @Published private(set) var user: GitHubUser?

    // Choose repository
    @Published var mode: Mode = .create
    @Published var newRepositoryName = "im-memory"
    @Published private(set) var repositories: [GitHubRepo] = []
    @Published var selectedRepositoryID: GitHubRepo.ID?

    // Working / done
    @Published private(set) var log: [String] = []
    @Published private(set) var connection: Connection?

    var close: () -> Void = {}

    private let appState: AppState
    private var token: String?

    init(appState: AppState) {
        self.appState = appState
        Task { await start() }
    }

    var canConnect: Bool {
        switch mode {
        case .create: !newRepositoryName.trimmingCharacters(in: .whitespaces).isEmpty
        case .existing: selectedRepositoryID != nil
        }
    }

    private func start() async {
        if let saved = TokenStore.load() {
            await signIn(with: saved)
            if user != nil { return }
            errorMessage = nil
        }
        cliToken = await Task.detached { GitHubCLI.token() }.value
    }

    func signInWithCLI() {
        guard let cliToken else { return }
        Task { await signIn(with: cliToken) }
    }

    func signInWithToken() {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await signIn(with: token) }
    }

    private func signIn(with token: String) async {
        await perform {
            self.user = try await GitHubClient(token: token).currentUser()
            try TokenStore.save(token)
            self.token = token
            self.step = .chooseRepository
        }
        if user != nil {
            await loadRepositories()
        }
    }

    func signOut() {
        TokenStore.delete()
        token = nil
        user = nil
        repositories = []
        selectedRepositoryID = nil
        tokenInput = ""
        errorMessage = nil
        step = .signIn
    }

    func loadRepositories() async {
        guard let token else { return }
        await perform {
            self.repositories = try await GitHubClient(token: token).privateRepositories()
        }
    }

    func connect() {
        guard let token, let user else { return }
        let client = GitHubClient(token: token)
        let mode = mode
        let name = newRepositoryName.trimmingCharacters(in: .whitespaces)
        let selected = repositories.first { $0.id == selectedRepositoryID }

        errorMessage = nil
        log = []
        step = .working
        appState.busy = true
        Task {
            defer { appState.busy = false }
            do {
                let repo: GitHubRepo
                switch mode {
                case .create:
                    append(L("Creating private repository \(user.login)/\(name)…", "正在创建私有仓库 \(user.login)/\(name)…"))
                    repo = try await client.createPrivateRepository(
                        name: name,
                        description: "Shared memory for my AI agents, managed by im."  // Stays English: it lives on GitHub.
                    )
                case .existing:
                    guard let selected else { return }
                    // Re-read it: visibility may have changed since the list was loaded.
                    repo = try await client.repository(fullName: selected.fullName)
                }
                guard repo.isPrivate else {
                    throw ConnectError.publicRepository(repo.fullName)
                }

                let setup = RepoSetup(
                    remoteURL: repo.cloneURL,
                    localPath: IMPaths.clone(of: repo.fullName),
                    defaultBranch: repo.defaultBranch ?? "main",
                    git: Git(token: token),
                    fallbackIdentity: .init(name: user.name ?? user.login, email: user.noreplyEmail),
                    log: { [weak self] message in Task { @MainActor in self?.append(message) } }
                )
                let result = try await Task.detached { try setup.run() }.value
                append(result.pushed
                    ? L("Initialized and pushed \(result.created.count) files.", "已初始化并推送 \(result.created.count) 个文件。")
                    : L("Nothing to change.", "没有需要改动的内容。"))

                let connection = Connection(fullName: repo.fullName, htmlURL: repo.htmlURL, localPath: setup.localPath)
                appState.connect(connection)
                self.connection = connection
                step = .done
            } catch {
                errorMessage = error.localizedDescription
                step = .chooseRepository
                if mode == .create {
                    await loadRepositories()
                }
            }
        }
    }

    private func append(_ message: String) {
        log.append(message)
    }

    private func perform(_ work: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ConnectError: LocalizedError {
    case publicRepository(String)

    var errorDescription: String? {
        switch self {
        case let .publicRepository(name):
            L("\(name) is public. im only works with private repositories, because memories and MCP configs can contain secrets.",
              "\(name) 是公开仓库。im 只使用私有仓库，因为记忆和 MCP 配置里可能有密钥。")
        }
    }
}
