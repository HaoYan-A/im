import Foundation

/// Every cat im can show: the built-ins plus the user's own in `~/.im/cats/`.
public struct CatLibrary: Sendable, Equatable {
    public struct Problem: Sendable, Equatable {
        public let file: String
        public let message: String
    }

    /// The built-in cats, where a custom cat with a built-in's id replaces it.
    public let builtins: [CatSkin]
    /// Custom cats with ids of their own, sorted by name.
    public let custom: [CatSkin]
    /// Custom cat files that could not be loaded.
    public let problems: [Problem]

    public var cats: [CatSkin] { builtins + custom }

    public static let builtinOnly = CatLibrary(custom: [], problems: [])

    init(custom: [CatSkin], problems: [Problem]) {
        let overrides = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        builtins = BuiltinCats.all.map { overrides[$0.id] ?? $0 }
        let builtinIDs = Set(BuiltinCats.all.map(\.id))
        self.custom = custom
            .filter { !builtinIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.problems = problems
    }

    public func cat(id: String) -> CatSkin? {
        cats.first { $0.id == id }
    }

    /// The cat to show for a configured id, falling back to the default for unknown ids.
    public func resolve(_ id: String?) -> CatSkin {
        id.flatMap(cat(id:)) ?? cat(id: BuiltinCats.defaultID)!
    }

    public static func load(from directory: URL = IMPaths.cats) -> CatLibrary {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var custom: [CatSkin] = []
        var problems: [Problem] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                custom.append(try CatSkin(id: file.deletingPathExtension().lastPathComponent, json: Data(contentsOf: file)))
            } catch {
                problems.append(Problem(file: file.lastPathComponent, message: error.localizedDescription))
            }
        }
        return CatLibrary(custom: custom, problems: problems)
    }

    /// Creates the cats folder with a README describing the format, if missing.
    public static func prepareDirectory(_ directory: URL = IMPaths.cats) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let readme = directory.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try Data(Self.readme.utf8).write(to: readme)
        }
    }

    private static var readme: String {
        let example = BuiltinCats.sources.first { $0.id == BuiltinCats.defaultID }!.json
        let ids = BuiltinCats.all.map { "`\($0.id)`" }.joined(separator: ", ")
        return """
        # Custom cats

        Every `<id>.json` file in this folder is a cat for the im menu bar. It appears in the **Cat** menu \
        as soon as it is saved, no restart needed. A file named after a built-in cat (\(ids)) replaces it.

        ## Format

        A cat is pixel art: each string in `awake` is one row, each character one pixel, colored by `palette`. \
        `.` is transparent. Each pixel is 1pt in the menu bar, so keep it around 18×17 and at most \
        \(CatSkin.maxWidth)×\(CatSkin.maxHeight).

        - `name`: shown in the menu (optional, defaults to the file name)
        - `palette`: one-character keys mapped to `#RRGGBB` or `#RRGGBBAA` colors
        - `awake`: the cat with its eyes open
        - `blink`: optional, same size as `awake`, shown when the cat blinks or sleeps

        Give the cat a dark outline so it stays visible on both light and dark menu bars.

        If a file has a mistake, the **Cat** menu lists it with the reason.

        ## Choosing a cat

        Pick one from the **Cat** menu, or set `cat` in `~/.im/config.json`. im picks up changes automatically, \
        so an AI agent can switch cats by editing that file:

        ```json
        { "cat": "my-cat" }
        ```

        ## Example: the built-in calico (`calico.json`)

        ```json
        \(example)
        ```

        """
    }
}

/// `~/.im/config.json`, the machine-local settings im and AI agents can both edit.
public enum IMConfig {
    public static var url: URL { IMPaths.home.appendingPathComponent("config.json") }

    public static func catID(at url: URL = url) -> String? {
        read(url)["cat"] as? String
    }

    /// Sets the cat, keeping any other keys already in the file.
    public static func setCatID(_ id: String, at url: URL = url) throws {
        var config = read(url)
        config["cat"] = id
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
