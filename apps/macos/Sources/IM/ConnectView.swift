import AppKit
import IMCore
import SwiftUI

@MainActor
final class ConnectWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(appState: AppState, catStore: CatStore, onClose: @escaping () -> Void) {
        let model = ConnectViewModel(appState: appState)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect Repository"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ConnectView(model: model, catStore: catStore))
        self.onClose = onClose
        super.init()
        window.delegate = self
        model.close = { [weak window] in window?.close() }
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
    @ObservedObject var catStore: CatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: catStore.skin.image(pointSize: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your memory").font(.title2.bold())
                    Text("im keeps memories, skills and MCP servers in a private GitHub repository.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch model.step {
            case .signIn: SignInStep(model: model)
            case .chooseRepository: ChooseRepositoryStep(model: model)
            case .working: WorkingStep(model: model)
            case .done: DoneStep(model: model)
            }

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
            Text("Sign in to GitHub").font(.headline)

            if model.cliToken != nil {
                Button("Continue with GitHub CLI login", action: model.signInWithCLI)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                Text("Or use a personal access token:").foregroundStyle(.secondary)
            } else {
                Text("Paste a personal access token with the `repo` scope.").foregroundStyle(.secondary)
            }

            SecureField("ghp_…", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.signInWithToken)

            HStack {
                Link("Create a token on GitHub…", destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=im")!)
                    .font(.callout)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button("Continue", action: model.signInWithToken)
                    .disabled(model.tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
                    .keyboardShortcut(.defaultAction)
            }

            Text("The token is stored in your macOS Keychain and never written to disk or git config.")
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
                Text("Signed in as **@\(user.login)**").foregroundStyle(.secondary)
            }

            Picker("", selection: $model.mode) {
                Text("Create new").tag(ConnectViewModel.Mode.create)
                Text("Use existing").tag(ConnectViewModel.Mode.existing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.mode {
            case .create:
                TextField("Repository name", text: $model.newRepositoryName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if model.canConnect { model.connect() } }
                Text("A new **private** repository will be created at github.com/\(model.user?.login ?? "you")/\(model.newRepositoryName).")
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
                        Text("No private repositories found.").foregroundStyle(.secondary)
                    }
                }
                Text("Only private repositories are listed. Public repositories are never used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("im adds a README and the `mcp/`, `skills/` and `memory/` folders. Existing files are never overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Use a different account", action: model.signOut)
                Spacer()
                Button(model.mode == .create ? "Create & Connect" : "Connect", action: model.connect)
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
                Label("Connected to **\(connection.fullName)**", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Local copy: \(connection.localPath.path)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Open on GitHub") { NSWorkspace.shared.open(connection.htmlURL) }
                    Button("Open Folder") { NSWorkspace.shared.open(connection.localPath) }
                    Spacer()
                    Button("Done", action: model.close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
