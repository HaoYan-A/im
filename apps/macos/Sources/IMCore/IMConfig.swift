import Foundation

/// `~/.im/config.json`, the machine-local settings im and AI agents can both edit.
public enum IMConfig {
    public static var url: URL { IMPaths.home.appendingPathComponent("config.json") }

    public static func catID(at url: URL = url) -> String? {
        read(url)["cat"] as? String
    }

    public static func setCatID(_ id: String, at url: URL = url) throws {
        try set("cat", to: id, at: url)
    }

    /// The configured language; unknown or missing values mean the default.
    public static func language(at url: URL = url) -> Language {
        (read(url)["language"] as? String).flatMap(Language.init(rawValue:)) ?? .default
    }

    public static func setLanguage(_ language: Language, at url: URL = url) throws {
        try set("language", to: language.rawValue, at: url)
    }

    /// Skills the user chose not to link; launch doesn't ask about them again.
    public static func skippedSkills(at url: URL = url) -> Set<String> {
        Set(read(url)["skippedSkills"] as? [String] ?? [])
    }

    public static func setSkippedSkills(_ names: Set<String>, at url: URL = url) throws {
        try set("skippedSkills", to: names.sorted(), at: url)
    }

    /// Sets one key, keeping any other keys already in the file.
    private static func set(_ key: String, to value: Any, at url: URL) throws {
        var config = read(url)
        config[key] = value
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
