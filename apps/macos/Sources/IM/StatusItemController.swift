import AppKit
import Combine
import IMCore

/// The cat in the menu bar and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private let preferences: Preferences
    private let showConnectWindow: () -> Void
    private let showSkillsWindow: (SkillsViewModel.Tab) -> Void
    private var animator: CatAnimator?
    private var subscriptions: Set<AnyCancellable> = []

    init(
        appState: AppState,
        preferences: Preferences,
        showConnectWindow: @escaping () -> Void,
        showSkillsWindow: @escaping (SkillsViewModel.Tab) -> Void
    ) {
        self.appState = appState
        self.preferences = preferences
        self.showConnectWindow = showConnectWindow
        self.showSkillsWindow = showSkillsWindow
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let animator = CatAnimator(skin: preferences.cat) { [weak statusItem] image in statusItem?.button?.image = image }
        self.animator = animator
        appState.$busy.combineLatest(appState.$connection)
            .sink { busy, connection in animator.mood = busy ? .busy : (connection == nil ? .asleep : .idle) }
            .store(in: &subscriptions)
        // @Published fires before the property changes, so resolve the skin from the emitted values.
        preferences.$library.combineLatest(preferences.$selectedCatID)
            .sink { library, id in animator.skin = library.resolve(id) }
            .store(in: &subscriptions)
    }

    // Rebuilt on every open so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let connection = appState.connection {
            menu.addItem(disabled: L("Connected to \(connection.fullName)", "已连接到 \(connection.fullName)"))
            menu.addItem(.separator())
            menu.addItem(title: L("Open on GitHub", "在 GitHub 上打开"), action: #selector(openOnGitHub), target: self)
            menu.addItem(title: L("Open Local Folder", "打开本地文件夹"), action: #selector(openLocalFolder), target: self)
            menu.addItem(.separator())
            menu.addItem(title: L("Skills…", "Skills…"), action: #selector(skills), target: self)
            menu.addItem(title: L("Get Skills from skills.sh…", "从 skills.sh 获取 Skill…"), action: #selector(discoverSkills), target: self)
            menu.addItem(.separator())
            menu.addItem(title: L("Change Repository…", "更换仓库…"), action: #selector(connect), target: self)
            menu.addItem(title: L("Disconnect", "断开连接"), action: #selector(disconnect), target: self)
        } else {
            menu.addItem(disabled: appState.busy ? L("Connecting…", "正在连接…") : L("Not connected", "未连接"))
            menu.addItem(.separator())
            menu.addItem(title: L("Connect Repository…", "连接仓库…"), action: #selector(connect), target: self)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: L("Cat", "小猫"), action: nil, keyEquivalent: "").submenu = makeCatMenu()
        menu.addItem(withTitle: L("Language", "语言"), action: nil, keyEquivalent: "").submenu = makeLanguageMenu()
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L("Quit im", "退出 im"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    private func makeCatMenu() -> NSMenu {
        let menu = NSMenu()
        let library = preferences.library
        let selected = preferences.cat.id

        func addCat(_ cat: CatSkin) {
            let item = menu.addItem(title: cat.localizedName, action: #selector(selectCat(_:)), target: self)
            item.representedObject = cat.id
            item.image = cat.image()
            item.state = cat.id == selected ? .on : .off
        }

        library.builtins.forEach(addCat)
        if !library.custom.isEmpty || !library.problems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled: L("Custom", "自定义"))
            library.custom.forEach(addCat)
            for problem in library.problems {
                menu.addItem(disabled: "⚠︎ \(problem.file): \(problem.message)")
            }
        }
        if let unknown = preferences.unknownCat {
            menu.addItem(.separator())
            menu.addItem(disabled: L("⚠︎ config.json asks for unknown cat \"\(unknown)\"", "⚠︎ config.json 里的小猫 \"\(unknown)\" 不存在"))
        }

        menu.addItem(.separator())
        menu.addItem(title: L("Open Cats Folder…", "打开小猫文件夹…"), action: #selector(openCatsFolder), target: self)
        return menu
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu()
        for language in Language.allCases {
            let item = menu.addItem(title: language.displayName, action: #selector(selectLanguage(_:)), target: self)
            item.representedObject = language.rawValue
            item.state = language == preferences.language ? .on : .off
        }
        return menu
    }

    @objc private func selectCat(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        preferences.selectCat(id)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = (sender.representedObject as? String).flatMap(Language.init(rawValue:)) else { return }
        preferences.selectLanguage(language)
    }

    @objc private func openCatsFolder() {
        do {
            try CatLibrary.prepareDirectory()
            NSWorkspace.shared.open(IMPaths.cats)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func skills() {
        showSkillsWindow(.installed)
    }

    @objc private func discoverSkills() {
        showSkillsWindow(.discover)
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
        guard let name = appState.connection?.fullName else { return }
        Task {
            let linked = await appState.linkedSkillCount()
            let alert = NSAlert()
            alert.messageText = L("Disconnect from \(name)?", "断开与 \(name) 的连接？")
            let keep = L("The repository and its local copy are not deleted.", "仓库和它的本地副本都不会被删除。")
            alert.informativeText = linked == 0 ? keep : L(
                "\(linked) linked skills will first be turned back into regular folders in Claude Code and Codex, so they keep working. \(keep)",
                "会先把 \(linked) 个已关联的 Skill 在 Claude Code 和 Codex 里还原成普通文件夹，保证它们继续可用。\(keep)"
            )
            alert.addButton(withTitle: L("Disconnect", "断开连接"))
            alert.addButton(withTitle: L("Cancel", "取消"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                try await appState.disconnect()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
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
