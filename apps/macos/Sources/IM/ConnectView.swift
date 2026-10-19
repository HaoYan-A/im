import AppKit
import Combine
import IMCore
import SwiftUI

@MainActor
final class ConnectWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void
    private var languageSubscription: AnyCancellable?

    init(appState: AppState, preferences: Preferences, onClose: @escaping () -> Void) {
        let model = ConnectViewModel(appState: appState)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ConnectView(model: model, preferences: preferences))
        self.onClose = onClose
        super.init()
        window.delegate = self
        model.close = { [weak window] in window?.close() }
        // Language.current is already switched when this fires.
        languageSubscription = preferences.$language.sink { [weak window] _ in
            window?.title = L("Connect Repository", "连接仓库")
        }
    }

    func show() {
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

struct ConnectView: View {
    @ObservedObject var model: ConnectViewModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: preferences.cat.image(pointSize: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Connect your memory", "连接你的记忆仓库")).font(.title2.bold())
                    Text(L("im keeps memories, skills and MCP servers in a private GitHub repository.",
                           "im 把记忆、Skills 和 MCP 服务都存放在一个私有 GitHub 仓库里。"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Group {
                switch model.step {
                case .signIn: SignInStep(model: model)
                case .chooseRepository: ChooseRepositoryStep(model: model)
                case .working: WorkingStep(model: model)
                case .done: DoneStep(model: model)
                }
            }
            // The steps read their text through L(), which SwiftUI can't track; rebuild them on a language switch.
            .id(preferences.language)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct SignInStep: View {
    @ObservedObject var model: ConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Sign in to GitHub", "登录 GitHub")).font(.headline)

            if model.cliToken != nil {
                Button(L("Continue with GitHub CLI login", "使用 GitHub CLI 的登录"), action: model.signInWithCLI)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                Text(L("Or use a personal access token:", "或者使用个人访问令牌：")).foregroundStyle(.secondary)
            } else {
                Text(markdown: L("Paste a personal access token with the `repo` scope.", "粘贴一个带 `repo` 权限的个人访问令牌。"))
                    .foregroundStyle(.secondary)
            }

            SecureField("ghp_…", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.signInWithToken)

            HStack {
                Link(L("Create a token on GitHub…", "在 GitHub 上创建令牌…"), destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=im")!)
                    .font(.callout)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button(L("Continue", "继续"), action: model.signInWithToken)
                    .disabled(model.tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
                    .keyboardShortcut(.defaultAction)
            }

            Text(L("The token is stored in your macOS Keychain and never written to disk or git config.",
                   "令牌保存在 macOS 钥匙串里，不会写进磁盘文件或 git 配置。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChooseRepositoryStep: View {
    @ObservedObject var model: ConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = model.user {
                Text(markdown: L("Signed in as **@\(user.login)**", "已登录：**@\(user.login)**")).foregroundStyle(.secondary)
            }

            Picker("", selection: $model.mode) {
                Text(L("Create new", "新建")).tag(ConnectViewModel.Mode.create)
                Text(L("Use existing", "使用已有仓库")).tag(ConnectViewModel.Mode.existing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.mode {
            case .create:
                TextField(L("Repository name", "仓库名称"), text: $model.newRepositoryName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if model.canConnect { model.connect() } }
                let path = "github.com/\(model.user?.login ?? "you")/\(model.newRepositoryName)"
                Text(markdown: L("A new **private** repository will be created at \(path).", "将在 \(path) 新建一个**私有**仓库。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .existing:
                List(model.repositories, selection: $model.selectedRepositoryID) { repo in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.fullName)
                        if let description = repo.description, !description.isEmpty {
                            Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(repo.id)
                }
                .frame(height: 180)
                .overlay {
                    if model.isLoading {
                        ProgressView()
                    } else if model.repositories.isEmpty {
                        Text(L("No private repositories found.", "没有找到私有仓库。")).foregroundStyle(.secondary)
                    }
                }
                Text(L("Only private repositories are listed. Public repositories are never used.",
                       "这里只列出私有仓库，公开仓库永远不会被使用。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(markdown: L("im adds a README and the `mcp/`, `skills/` and `memory/` folders. Existing files are never overwritten.",
                             "im 会添加 README 以及 `mcp/`、`skills/`、`memory/` 文件夹，已有的文件不会被覆盖。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L("Use a different account", "换一个账号"), action: model.signOut)
                Spacer()
                Button(model.mode == .create ? L("Create & Connect", "新建并连接") : L("Connect", "连接"), action: model.connect)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConnect || model.isLoading)
            }
        }
    }
}

private struct WorkingStep: View {
    @ObservedObject var model: ConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView().controlSize(.small)
            ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DoneStep: View {
    @ObservedObject var model: ConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let connection = model.connection {
                Label {
                    Text(markdown: L("Connected to **\(connection.fullName)**", "已连接到 **\(connection.fullName)**"))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                Text(L("Local copy: \(connection.localPath.path)", "本地副本：\(connection.localPath.path)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button(L("Open on GitHub", "在 GitHub 上打开")) { NSWorkspace.shared.open(connection.htmlURL) }
                    Button(L("Open Folder", "打开文件夹")) { NSWorkspace.shared.open(connection.localPath) }
                    Spacer()
                    Button(L("Done", "完成"), action: model.close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

private extension Text {
    /// Text whose inline Markdown (bold, code) is rendered; plain `Text(String)` shows it verbatim.
    init(markdown: String) {
        self.init((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
    }
}
