import Foundation
import IMCore

/// The chosen cat and the cat library, kept in sync with `~/.im/config.json` and `~/.im/cats/`
/// so changes made by hand or by an AI agent show up right away.
@MainActor
final class CatStore: ObservableObject {
    @Published private(set) var library = CatLibrary.builtinOnly
    /// The id from config.json; may name a cat that doesn't exist.
    @Published private(set) var selectedID: String?

    var skin: CatSkin { library.resolve(selectedID) }

    /// Set when config.json names a cat that isn't in the library.
    var unknownSelection: String? {
        selectedID.flatMap { library.cat(id: $0) == nil ? $0 : nil }
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

    func select(_ id: String) {
        do {
            try IMConfig.setCatID(id)
        } catch {
            NSLog("im: could not save cat choice: \(error)")
        }
        selectedID = id
    }

    private func reloadIfChanged() {
        let current = Self.fingerprint()
        guard current != fingerprint else { return }
        fingerprint = current
        let library = CatLibrary.load()
        if library != self.library { self.library = library }
        let id = IMConfig.catID()
        if id != selectedID { selectedID = id }
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
