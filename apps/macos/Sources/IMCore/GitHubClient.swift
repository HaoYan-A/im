import Foundation

public struct GitHubUser: Decodable, Sendable, Equatable {
    public let id: Int
    public let login: String
    public let name: String?

    /// Commit email that does not expose the user's real address.
    public var noreplyEmail: String { "\(id)+\(login)@users.noreply.github.com" }
}

public struct GitHubRepo: Decodable, Sendable, Identifiable, Hashable {
    public struct Permissions: Decodable, Sendable, Hashable {
        public let push: Bool
    }

    public let id: Int
    public let name: String
    public let fullName: String
    public let description: String?
    public let isPrivate: Bool
    public let htmlURL: URL
    public let cloneURL: URL
    public let defaultBranch: String?
    public let permissions: Permissions?

    enum CodingKeys: String, CodingKey {
        case id, name, description, permissions
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case defaultBranch = "default_branch"
    }
}

/// A recursive listing from the git trees API.
public struct GitTree: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Equatable {
        public let path: String
        /// "blob" for files, "tree" for folders.
        public let type: String
        public let sha: String

        public init(path: String, type: String, sha: String) {
            self.path = path
            self.type = type
            self.sha = sha
        }
    }

    public let sha: String
    public let tree: [Entry]
    /// GitHub cuts very large trees short.
    public let truncated: Bool

    public init(sha: String, tree: [Entry], truncated: Bool = false) {
        self.sha = sha
        self.tree = tree
        self.truncated = truncated
    }
}

public enum GitHubError: LocalizedError {
    case unauthorized
    case api(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            L("GitHub rejected the token. Make sure it is valid and has the `repo` scope.",
              "GitHub 拒绝了这个令牌。请确认它有效，并且带有 `repo` 权限。")
        case let .api(status, message):
            L("GitHub API error \(status): \(message)", "GitHub API 错误 \(status)：\(message)")
        }
    }
}

/// Minimal GitHub REST client covering what im needs to connect a repository.
public struct GitHubClient: Sendable {
    public let token: String
    private let session: URLSession
    private static let api = URL(string: "https://api.github.com")!

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func currentUser() async throws -> GitHubUser {
        try await send("GET", "user")
    }

    /// Private repositories the user can push to, most recently updated first.
    public func privateRepositories() async throws -> [GitHubRepo] {
        var repos: [GitHubRepo] = []
        for page in 1... {
            let batch: [GitHubRepo] = try await send("GET", "user/repos", query: [
                "visibility": "private",
                "sort": "updated",
                "per_page": "100",
                "page": String(page),
            ])
            repos += batch.filter { $0.isPrivate && $0.permissions?.push != false }
            if batch.count < 100 { break }
        }
        return repos
    }

    public func repository(fullName: String) async throws -> GitHubRepo {
        try await send("GET", "repos/\(fullName)")
    }

    /// Every file and folder of a repository at `ref` (a branch, commit or tree SHA), recursively.
    public func tree(_ repository: String, ref: String) async throws -> GitTree {
        try await send("GET", "repos/\(repository)/git/trees/\(ref)", query: ["recursive": "1"])
    }

    public func blob(_ repository: String, sha: String) async throws -> Data {
        struct Blob: Decodable { let content: String; let encoding: String }
        let blob: Blob = try await send("GET", "repos/\(repository)/git/blobs/\(sha)")
        guard blob.encoding == "base64", let data = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters) else {
            throw GitHubError.api(status: 200, message: "unexpected blob encoding \(blob.encoding)")
        }
        return data
    }

    /// Creates an empty repository owned by the user. It is always private.
    public func createPrivateRepository(name: String, description: String) async throws -> GitHubRepo {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": description,
            "private": true,
            "auto_init": false,
        ])
        return try await send("POST", "user/repos", body: body)
    }

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) async throws -> T {
        var components = URLComponents(url: Self.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw GitHubError.unauthorized }
        guard (200..<300).contains(status) else {
            throw GitHubError.api(status: status, message: Self.errorMessage(from: data))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        struct Body: Decodable {
            struct Item: Decodable { let message: String? }
            let message: String
            let errors: [Item]?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return String(decoding: data, as: UTF8.self)
        }
        let details = body.errors?.compactMap(\.message) ?? []
        return ([body.message] + details).joined(separator: " — ")
    }
}
