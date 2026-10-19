import Foundation

/// A pixel-art cat: rows of characters, each mapped to a color by the palette. `.` is transparent.
///
/// Built-in cats and user cats in `~/.im/cats/<id>.json` share this JSON format:
///
///     {
///       "name": "Calico",
///       "names": { "zh-Hans": "三花" },  // optional translations of "name"
///       "palette": { "k": "#2A211E", "w": "#FAF6F0" },
///       "awake": ["..kk..", ".kwwk.", ...],
///       "blink": [...]            // optional, same size as "awake"
///     }
public struct CatSkin: Sendable, Identifiable, Equatable {
    public struct Color: Sendable, Equatable {
        public let red, green, blue, alpha: Double
    }

    /// The menu bar is about 22pt tall and the busy animation needs one spare row.
    public static let maxWidth = 24
    public static let maxHeight = 20

    public let id: String
    public let name: String
    /// Translated names keyed by language code, e.g. `zh-Hans`.
    public let names: [String: String]
    public let palette: [Character: Color]
    public let awake: [String]
    public let blink: [String]?

    /// The name in the current language, falling back to `name`.
    public var localizedName: String { names[Language.current.rawValue] ?? name }

    public var width: Int { awake[0].count }
    public var height: Int { awake.count }
}

public enum CatSkinError: LocalizedError, Equatable {
    case invalidJSON(String)
    case empty
    case tooLarge(width: Int, height: Int)
    case unevenRows(frame: String)
    case frameSizeMismatch(frame: String)
    case invalidPaletteKey(String)
    case invalidColor(key: String, value: String)
    case unknownPixel(Character, frame: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSON(detail):
            L("not valid cat JSON (\(detail))", "不是有效的小猫 JSON（\(detail)）")
        case .empty:
            L("\"awake\" has no rows", "\"awake\" 没有任何行")
        case let .tooLarge(width, height):
            L("\(width)×\(height) is too large, the maximum is \(CatSkin.maxWidth)×\(CatSkin.maxHeight)",
              "\(width)×\(height) 太大了，最大是 \(CatSkin.maxWidth)×\(CatSkin.maxHeight)")
        case let .unevenRows(frame):
            L("rows in \"\(frame)\" have different lengths", "\"\(frame)\" 里的行长度不一致")
        case let .frameSizeMismatch(frame):
            L("\"\(frame)\" must be the same size as \"awake\"", "\"\(frame)\" 必须和 \"awake\" 一样大")
        case let .invalidPaletteKey(key):
            L("palette key \"\(key)\" must be a single character other than \".\"", "调色板的键 \"\(key)\" 必须是单个字符，且不能是 \".\"")
        case let .invalidColor(key, value):
            L("palette color \"\(value)\" for \"\(key)\" is not #RRGGBB or #RRGGBBAA", "\"\(key)\" 的颜色 \"\(value)\" 不是 #RRGGBB 或 #RRGGBBAA 格式")
        case let .unknownPixel(pixel, frame):
            L("\"\(frame)\" uses \"\(pixel)\", which is not in the palette", "\"\(frame)\" 用到了调色板里没有的 \"\(pixel)\"")
        }
    }
}

extension CatSkin {
    private struct File: Decodable {
        let name: String?
        let names: [String: String]?
        let palette: [String: String]
        let awake: [String]
        let blink: [String]?
    }

    public init(id: String, json: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch let error as DecodingError {
            throw CatSkinError.invalidJSON(Self.describe(error))
        }

        var palette: [Character: Color] = [:]
        for (key, value) in file.palette {
            guard key.count == 1, key != "." else { throw CatSkinError.invalidPaletteKey(key) }
            guard let color = Color(hex: value) else { throw CatSkinError.invalidColor(key: key, value: value) }
            palette[Character(key)] = color
        }

        try Self.validate(file.awake, frame: "awake", palette: palette)
        if let blink = file.blink {
            try Self.validate(blink, frame: "blink", palette: palette)
            guard blink.count == file.awake.count, blink[0].count == file.awake[0].count else {
                throw CatSkinError.frameSizeMismatch(frame: "blink")
            }
        }

        self.init(id: id, name: file.name ?? id, names: file.names ?? [:], palette: palette, awake: file.awake, blink: file.blink)
    }

    private static func validate(_ rows: [String], frame: String, palette: [Character: Color]) throws {
        guard let width = rows.first?.count, width > 0 else { throw CatSkinError.empty }
        guard rows.allSatisfy({ $0.count == width }) else { throw CatSkinError.unevenRows(frame: frame) }
        guard width <= maxWidth, rows.count <= maxHeight else {
            throw CatSkinError.tooLarge(width: width, height: rows.count)
        }
        for row in rows {
            if let pixel = row.first(where: { $0 != "." && palette[$0] == nil }) {
                throw CatSkinError.unknownPixel(pixel, frame: frame)
            }
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, _): L("missing \"\(key.stringValue)\"", "缺少 \"\(key.stringValue)\"")
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            context.codingPath.isEmpty
                ? context.debugDescription
                : "\"\(context.codingPath.map(\.stringValue).joined(separator: "."))\": \(context.debugDescription)"
        @unknown default: error.localizedDescription
        }
    }
}

extension CatSkin.Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        red = Double(rgba >> 24 & 0xFF) / 255
        green = Double(rgba >> 16 & 0xFF) / 255
        blue = Double(rgba >> 8 & 0xFF) / 255
        alpha = Double(rgba & 0xFF) / 255
    }
}
