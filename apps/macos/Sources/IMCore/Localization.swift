import Foundation

/// The languages im speaks. English is the default, independent of the system language.
public enum Language: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public static let `default` = Language.english

    /// Always written in the language itself, so it can be found from either one.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current = Language.default

    /// The language every `L(_:_:)` call uses.
    public static var current: Language {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}

/// Picks the English or Chinese text for the current language.
///
/// Both translations sit next to each other at the call site, so neither can go missing.
public func L(_ english: String, _ chinese: String) -> String {
    switch Language.current {
    case .english: english
    case .chinese: chinese
    }
}
