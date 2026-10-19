import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = StatusItemController(
            appState: appState,
            preferences: preferences,
            showConnectWindow: { [weak self] in self?.showConnectWindow() },
            showSkillsWindow: { [weak self] in self?.showSkillsWindow() }
        )
        if appState.connection == nil {
            showConnectWindow()
        } else {
            offerSkills()
        }
    }

    private func showConnectWindow() {
        if connectWindow == nil {
            connectWindow = ConnectWindowController(appState: appState, preferences: preferences) { [weak self] in
                self?.connectWindow = nil
                self?.offerSkills()
            }
        }
        connectWindow?.show()
    }

    /// Opens the Skills window and reloads it.
    private func showSkillsWindow() {
        let controller = skillsWindow ?? makeSkillsWindow()
        skillsWindow = controller
        controller.show()
        Task { await controller.model.reload() }
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
