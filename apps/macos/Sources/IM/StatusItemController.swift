import AppKit
import Combine
import IMCore

/// The cat in the menu bar and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private let catStore: CatStore
    private let showConnectWindow: () -> Void
    private var animator: CatAnimator?
    private var subscriptions: Set<AnyCancellable> = []

    init(appState: AppState, catStore: CatStore, showConnectWindow: @escaping () -> Void) {
        self.appState = appState
        self.catStore = catStore
        self.showConnectWindow = showConnectWindow
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let animator = CatAnimator(skin: catStore.skin) { [weak statusItem] image in statusItem?.button?.image = image }
        self.animator = animator
        appState.$busy.combineLatest(appState.$connection)
            .sink { busy, connection in animator.mood = busy ? .busy : (connection == nil ? .asleep : .idle) }
            .store(in: &subscriptions)
        // @Published fires before the property changes, so resolve the skin from the emitted values.
        catStore.$library.combineLatest(catStore.$selectedID)
            .sink { library, id in animator.skin = library.resolve(id) }
            .store(in: &subscriptions)
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
        menu.addItem(withTitle: "Cat", action: nil, keyEquivalent: "").submenu = makeCatMenu()
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit im", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    private func makeCatMenu() -> NSMenu {
        let menu = NSMenu()
        let library = catStore.library
        let selected = catStore.skin.id

        func addCat(_ cat: CatSkin) {
            let item = menu.addItem(title: cat.name, action: #selector(selectCat(_:)), target: self)
            item.representedObject = cat.id
            item.image = cat.image()
            item.state = cat.id == selected ? .on : .off
        }

        library.builtins.forEach(addCat)
        if !library.custom.isEmpty || !library.problems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled: "Custom")
            library.custom.forEach(addCat)
            for problem in library.problems {
                menu.addItem(disabled: "⚠︎ \(problem.file): \(problem.message)")
            }
        }
        if let unknown = catStore.unknownSelection {
            menu.addItem(.separator())
            menu.addItem(disabled: "⚠︎ config.json asks for unknown cat \"\(unknown)\"")
        }

        menu.addItem(.separator())
        menu.addItem(title: "Open Cats Folder…", action: #selector(openCatsFolder), target: self)
        return menu
    }

    @objc private func selectCat(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        catStore.select(id)
    }

    @objc private func openCatsFolder() {
        do {
            try CatLibrary.prepareDirectory()
            NSWorkspace.shared.open(IMPaths.cats)
        } catch {
            NSAlert(error: error).runModal()
        }
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

    @discardableResult
    func addItem(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
        return item
    }
}
