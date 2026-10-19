import AppKit
import IMCore

@main
@MainActor
enum IMApp {
    static func main() {
        Preferences.applySavedLanguage()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock icon, no app switcher entry.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let preferences = Preferences()
    private var statusItem: StatusItemController?
    private var connectWindow: ConnectWindowController?
    private var skillsWindow: SkillsWindowController?
    private var skillsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = StatusItemController(
            appState: appState,
            preferences: preferences,
            showConnectWindow: { [weak self] in self?.showConnectWindow() },
            showSkillsWindow: { [weak self] tab in self?.showSkillsWindow(tab: tab) }
        )
        // Launch already checks (offerSkills); after that, look for upstream skill updates every 6 hours.
        skillsTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintainSkills() }
        }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["IM_SNAPSHOT_SKILLS"] {
            return snapshotSkillsWindow(to: path)
        }
        #endif
        if appState.connection == nil {
            showConnectWindow()
        } else {
            offerSkills()
        }
    }

    #if DEBUG
    /// Design review aid: renders the Skills window to a PNG and quits. No screen-recording permission needed.
    private func snapshotSkillsWindow(to path: String) {
        if ProcessInfo.processInfo.environment["IM_SNAPSHOT_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if ProcessInfo.processInfo.environment["IM_SNAPSHOT_ENGLISH"] != nil { Language.current = .english }
        let controller = makeSkillsWindow()
        skillsWindow = controller
        controller.show()
        Task {
            let environment = ProcessInfo.processInfo.environment
            await controller.model.reload(sync: environment["IM_SNAPSHOT_MAINTAIN"] != nil)
            if environment["IM_SNAPSHOT_SELECT_ALL"] != nil { controller.model.selectAll(true) }
            if let query = environment["IM_SNAPSHOT_DISCOVER"] {
                controller.model.tab = .discover
                controller.discover.query = query
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let view = NSApp.keyWindow?.contentView ?? NSApp.windows.first(where: \.isVisible)?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
    #endif

    private func showConnectWindow() {
        if connectWindow == nil {
            connectWindow = ConnectWindowController(appState: appState, preferences: preferences) { [weak self] in
                self?.connectWindow = nil
                self?.offerSkills()
            }
        }
        connectWindow?.show()
    }

    /// Opens the Skills window on `tab` and reloads it.
    private func showSkillsWindow(tab: SkillsViewModel.Tab = .installed) {
        let controller = skillsWindow ?? makeSkillsWindow()
        skillsWindow = controller
        controller.model.tab = tab
        controller.show()
        Task { await controller.model.reload() }
    }

    /// Syncs skills and applies upstream updates, in the open Skills window or in the background.
    private func maintainSkills() {
        if let controller = skillsWindow {
            Task { await controller.model.reload() }
            return
        }
        guard let context = SkillsViewModel(appState: appState).context() else { return }
        Task.detached {
            let report = await SkillMaintenance.run(environment: context.environment, sync: context.sync(), upstream: context.upstream())
            if !report.updated.isEmpty || report.syncError != nil {
                NSLog("im: skills updated \(report.updated), sync error: \(report.syncError ?? "none")")
            }
        }
    }

    /// Scans in the background and opens the Skills window only if a skill is waiting for a decision.
    private func offerSkills() {
        guard appState.connection != nil, skillsWindow == nil else { return }
        let controller = makeSkillsWindow()
        Task {
            await controller.model.reload()
            guard !controller.model.pending.isEmpty, skillsWindow == nil else { return }
            skillsWindow = controller
            controller.show()
        }
    }

    private func makeSkillsWindow() -> SkillsWindowController {
        SkillsWindowController(appState: appState, preferences: preferences) { [weak self] in self?.skillsWindow = nil }
    }

    /// Never visible for an accessory app, but text fields need it for ⌘C / ⌘V / ⌘A and windows for ⌘W.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit im", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "im", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        return main
    }
}
