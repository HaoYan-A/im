import AppKit
import Combine

/// The cat in the menu bar and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private let showConnectWindow: () -> Void
    private var animator: CatAnimator?
    private var subscription: AnyCancellable?

    init(appState: AppState, showConnectWindow: @escaping () -> Void) {
        self.appState = appState
        self.showConnectWindow = showConnectWindow
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let animator = CatAnimator { [weak statusItem] image in statusItem?.button?.image = image }
        self.animator = animator
        subscription = appState.$busy.combineLatest(appState.$connection).sink { busy, connection in
            animator.mood = busy ? .busy : (connection == nil ? .asleep : .idle)
        }
    }

    // Rebuilt on every open so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let connection = appState.connection {
            menu.addItem(disabled: "Connected to \(connection.fullName)")
            menu.addItem(.separator())
            menu.addItem(title: "Open on GitHub", action: #selector(openOnGitHub), target: self)
            menu.addItem(title: "Open Local Folder", action: #selector(openLocalFolder), target: self)
            menu.addItem(.separator())
            menu.addItem(title: "Change Repository…", action: #selector(connect), target: self)
            menu.addItem(title: "Disconnect", action: #selector(disconnect), target: self)
        } else {
            menu.addItem(disabled: appState.busy ? "Connecting…" : "Not connected")
            menu.addItem(.separator())
            menu.addItem(title: "Connect Repository…", action: #selector(connect), target: self)
        }

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit im", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    @objc private func connect() {
        showConnectWindow()
    }

    @objc private func openOnGitHub() {
        guard let url = appState.connection?.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openLocalFolder() {
        guard let url = appState.connection?.localPath else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func disconnect() {
        appState.disconnect()
    }
}

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addItem(title: String, action: Selector, target: AnyObject) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}
