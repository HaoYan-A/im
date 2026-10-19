import CryptoKit
import Foundation

/// Where a skill comes from upstream: a folder in a GitHub repository, as listed on skills.sh.
public struct SkillSource: Codable, Sendable, Hashable {
    /// `owner/repo`.
    public var repository: String
    /// The skill folder inside the repository, e.g. `skills/productivity/grill-me`.
    public var path: String
    /// Git tree SHA of the upstream folder the im copy is based on.
    public var treeSHA: String

    public init(repository: String, path: String, treeSHA: String) {
        self.repository = repository
        self.path = path
        self.treeSHA = treeSHA
    }

    public var slug: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// The skill's page on skills.sh.
    public var pageURL: URL { URL(string: "https://skills.sh/\(repository)/\(slug)")! }

    /// Only plain `owner/repo` GitHub sources are supported, not well-known domains.
    static func isGitHubRepository(_ source: String) -> Bool {
        let parts = source.split(separator: "/", omittingEmptySubsequences: false)
        // GitHub owners can't contain dots; well-known sources are domains like "mintlify.com".
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } && !parts[0].contains(".")
    }

    /// Sources recorded by the skills CLI (`npx skills add`) in `~/.agents/.skill-lock.json`.
    public static func fromSkillsLockFile(home: URL) -> [String: SkillSource] {
        struct Lock: Decodable {
            struct Entry: Decodable {
                let source: String
                let sourceType: String?
                let skillPath: String?
                let skillFolderHash: String?
            }
            let skills: [String: Entry]
        }
        let url = home.appendingPathComponent(".agents/.skill-lock.json")
        guard let data = try? Data(contentsOf: url), let lock = try? JSONDecoder().decode(Lock.self, from: data) else { return [:] }
        var sources: [String: SkillSource] = [:]
        for (name, entry) in lock.skills {
            guard entry.sourceType ?? "github" == "github", isGitHubRepository(entry.source),
                  let skillPath = entry.skillPath, let hash = entry.skillFolderHash, !hash.isEmpty
            else { continue }
            let folder = skillPath.hasSuffix("/SKILL.md") ? String(skillPath.dropLast("/SKILL.md".count)) : skillPath
            sources[name] = SkillSource(repository: entry.source, path: folder, treeSHA: hash)
        }
        return sources
    }
}

extension GitTree {
    /// A folder's tree SHA and its files (relative path → blob SHA), from a recursive listing.
    public func folder(_ path: String) -> (sha: String, blobs: [String: String])? {
        guard let folder = tree.first(where: { $0.path == path && $0.type == "tree" }) else { return nil }
        let prefix = path + "/"
        var blobs: [String: String] = [:]
        for entry in tree where entry.type == "blob" && entry.path.hasPrefix(prefix) {
            blobs[String(entry.path.dropFirst(prefix.count))] = entry.sha
        }
        return (folder.sha, blobs)
    }

    /// Every file in this tree (relative path → blob SHA); for a tree fetched by a folder's SHA.
    public var blobs: [String: String] {
        Dictionary(tree.filter { $0.type == "blob" }.map { ($0.path, $0.sha) }, uniquingKeysWith: { first, _ in first })
    }

    /// Folders holding a SKILL.md whose folder name is `name`, shallowest first.
    public func skillFolders(named name: String) -> [String] {
        tree
            .filter { $0.type == "blob" && ($0.path == "\(name)/SKILL.md" || $0.path.hasSuffix("/\(name)/SKILL.md")) }
            .map { String($0.path.dropLast("/SKILL.md".count)) }
            .sorted { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }
    }
}

/// Git blob SHAs of a local folder, comparable with a `GitTree` without downloading anything.
public enum SkillBlobs {
    public static func of(_ folder: URL) -> [String: String] {
        var blobs: [String: String] = [:]
        for file in SkillScanner.regularFiles(in: folder.resolvingSymlinksInPath()) {
            guard let data = try? Data(contentsOf: file.url) else { continue }
            blobs[file.path] = gitBlobSHA(data)
        }
        return blobs
    }

    /// What `git hash-object` prints for this content.
    static func gitBlobSHA(_ data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\u{0}".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads skill folders from GitHub. `GitHubClient` in the app, a fake in tests.
public protocol SkillUpstream: Sendable {
    func tree(_ repository: String, ref: String) async throws -> GitTree
    func blob(_ repository: String, sha: String) async throws -> Data
}

extension GitHubClient: SkillUpstream {}

extension SkillUpstream {
    /// Writes the given files of `repository` into `folder`, which must not exist yet.
    func download(_ blobs: [String: String], from repository: String, to folder: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, sha) in blobs.sorted(by: { $0.key < $1.key }) {
            let file = folder.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await blob(repository, sha: sha).write(to: file)
        }
    }
}

/// A skill listed on skills.sh.
public struct SkillHubResult: Decodable, Sendable, Identifiable, Hashable {
    /// `owner/repo/skill`.
    public let id: String
    /// `owner/repo`, or a domain for well-known sources.
    public let source: String
    public let skillId: String
    public let name: String
    public let installs: Int

    public init(id: String, source: String, skillId: String, name: String, installs: Int) {
        self.id = id
        self.source = source
        self.skillId = skillId
        self.name = name
        self.installs = installs
    }

    public var isInstallable: Bool { SkillSource.isGitHubRepository(source) }
    public var pageURL: URL { URL(string: "https://skills.sh/\(id)")! }
}

public enum SkillHubError: LocalizedError {
    case searchFailed(status: Int)

    public var errorDescription: String? {
        switch self {
        case let .searchFailed(status):
            L("skills.sh search failed (HTTP \(status)). Try again later.", "skills.sh 搜索失败（HTTP \(status)），请稍后再试。")
        }
    }
}

public protocol SkillHubSearching: Sendable {
    func search(_ query: String, limit: Int) async throws -> [SkillHubResult]
}

/// Search on skills.sh. Uses the endpoint the `npx skills` CLI uses: the documented v1 API
/// needs a Vercel OIDC token, which a desktop app can't get.
public struct SkillHub: SkillHubSearching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(_ query: String, limit: Int = 30) async throws -> [SkillHubResult] {
        struct Response: Decodable { let skills: [SkillHubResult] }
        var components = URLComponents(string: "https://skills.sh/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        let (data, response) = try await session.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SkillHubError.searchFailed(status: status) }
        return try JSONDecoder().decode(Response.self, from: data).skills
    }
}
