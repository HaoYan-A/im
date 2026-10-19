import Foundation
import Security

/// Stores the GitHub token in the macOS Keychain.
public enum TokenStore {
    private static let service = "io.github.haoyan-a.im"
    private static let account = "github"

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    public static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ token: String) throws {
        delete()
        var query = baseQuery
        query[kSecValueData] = Data(token.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Could not save the token to the Keychain (\(status)).",
            ])
        }
    }

    public static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Reuses an existing GitHub CLI (`gh`) login when one is available.
public enum GitHubCLI {
    // GUI apps do not inherit the shell PATH, so look in the usual install locations.
    private static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    /// The token `gh` is logged in with, or nil if gh is missing or logged out. Blocks; call off the main thread.
    public static func token() -> String? {
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let output = try? Command.run(URL(fileURLWithPath: path), ["auth", "token", "--hostname", "github.com"])
        else { return nil }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
