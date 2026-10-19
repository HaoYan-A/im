import Foundation
import IMCore

/// The chosen cat and language plus the cat library, kept in sync with `~/.im/config.json` and
/// `~/.im/cats/` so changes made by hand or by an AI agent show up right away.
@MainActor
final class Preferences: ObservableObject {
    @Published private(set) var library = CatLibrary.builtinOnly
    /// The id from config.json; may name a cat that doesn't exist.
    @Published private(set) var selectedCatID: String?
    @Published private(set) var language = Language.default

    var cat: CatSkin { library.resolve(selectedCatID) }

    /// Set when config.json names a cat that isn't in the library.
    var unknownCat: String? {
        selectedCatID.flatMap { library.cat(id: $0) == nil ? $0 : nil }
    }

    private var fingerprint = ""
    private var timer: Timer?

    init() {
        reloadIfChanged()
        // Polling two small paths is cheap and, unlike directory watchers, also catches in-place edits.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChanged() }
        }
    }

    func selectCat(_ id: String) {
        save { try IMConfig.setCatID(id) }
        selectedCatID = id
    }

    func selectLanguage(_ language: Language) {
        save { try IMConfig.setLanguage(language) }
        apply(language)
    }

    /// Reads the language before any UI exists, so the first window already uses it.
    static func applySavedLanguage() {
        let language = IMConfig.language()
        Language.current = language
        Self.setSystemLanguage(language)
    }

    private func apply(_ language: Language) {
        guard language != self.language else { return }
        Language.current = language
        Self.setSystemLanguage(language)
        self.language = language
    }

    /// AppKit's own strings (alert buttons, text field menus) follow AppleLanguages from the next launch.
    private static func setSystemLanguage(_ language: Language) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    private func save(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            NSLog("im: could not save preferences: \(error)")
        }
    }

    private func reloadIfChanged() {
        let current = Self.fingerprint()
        guard current != fingerprint else { return }
        fingerprint = current
        // Language first: library and cat observers render names in it.
        apply(IMConfig.language())
        let library = CatLibrary.load()
        if library != self.library { self.library = library }
        let id = IMConfig.catID()
        if id != selectedCatID { selectedCatID = id }
    }

    /// Changes whenever config.json or any file in the cats folder is added, removed or modified.
    private static func fingerprint() -> String {
        let fm = FileManager.default
        func stamp(_ url: URL) -> String {
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = attributes?[.size] as? Int ?? -1
            return "\(url.lastPathComponent):\(date):\(size)"
        }
        let cats = (try? fm.contentsOfDirectory(at: IMPaths.cats, includingPropertiesForKeys: nil)) ?? []
        return ([IMConfig.url] + cats.sorted { $0.path < $1.path }).map(stamp).joined(separator: "|")
    }
}
