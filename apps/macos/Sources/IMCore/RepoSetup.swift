import Foundation

public enum IMPaths {
    /// `~/.im`, the same place on every platform.
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".im", isDirectory: true)
    }

    /// Local clone of a memory repository, e.g. `~/.im/repos/octocat/im-memory`.
    public static func clone(of fullName: String) -> URL {
        home.appendingPathComponent("repos", isDirectory: true).appendingPathComponent(fullName, isDirectory: true)
    }
}

public enum RepoSetupError: LocalizedError {
    case localPathInUse(URL)

    public var errorDescription: String? {
        switch self {
        case let .localPathInUse(url):
            "\(url.path) already exists and is not a clone of this repository. Move it away and try again."
        }
    }
}

/// Clones a memory repository (or reuses an existing clone), adds the im layout and pushes it.
public struct RepoSetup: Sendable {
    public struct Identity: Sendable {
        public let name: String
        public let email: String

        public init(name: String, email: String) {
            self.name = name
            self.email = email
        }
    }

    public struct Result: Sendable {
        /// Paths added by the scaffold; empty when the repository was already initialized.
        public let created: [String]
        public let pushed: Bool
    }

    public let remoteURL: URL
    public let localPath: URL
    /// Branch to start on when the remote repository is empty.
    public let defaultBranch: String
    public let git: Git
    /// Commit identity used only when git has none configured.
    public let fallbackIdentity: Identity
    public let log: @Sendable (String) -> Void

    public init(
        remoteURL: URL,
        localPath: URL,
        defaultBranch: String,
        git: Git,
        fallbackIdentity: Identity,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.remoteURL = remoteURL
        self.localPath = localPath
        self.defaultBranch = defaultBranch
        self.git = git
        self.fallbackIdentity = fallbackIdentity
        self.log = log
    }

    /// Blocks while git runs; call off the main thread.
    @discardableResult
    public func run() throws -> Result {
        try prepareClone()

        if !resolves("HEAD") {
            // Nothing checked out: either the remote is empty, or its HEAD points at a branch that doesn't exist.
            if resolves("refs/remotes/origin/\(defaultBranch)") {
                try git.run(["checkout", "--quiet", "-B", defaultBranch, "origin/\(defaultBranch)"], in: localPath)
            } else {
                try git.run(["symbolic-ref", "HEAD", "refs/heads/\(defaultBranch)"], in: localPath)
            }
        }

        log("Creating the im layout…")
        let created = try RepoScaffold.apply(at: localPath)
        guard !created.isEmpty else {
            log("Repository is already initialized.")
            return Result(created: [], pushed: false)
        }

        try ensureIdentity()
        try git.run(["add", "--"] + created, in: localPath)
        try git.run(["commit", "--quiet", "-m", "chore(im): initialize repository layout"], in: localPath)
        log("Pushing to GitHub…")
        try git.run(["push", "--quiet", "-u", "origin", "HEAD"], in: localPath)
        return Result(created: created, pushed: true)
    }

    private func prepareClone() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: localPath.appendingPathComponent(".git").path) {
            let origin = try? git.run(["remote", "get-url", "origin"], in: localPath)
            guard let origin, Self.sameRemote(origin, remoteURL.absoluteString) else {
                throw RepoSetupError.localPathInUse(localPath)
            }
            log("Updating the existing local copy…")
            try git.run(["fetch", "--quiet", "origin"], in: localPath)
            let remoteHasBranches = !(try git.run(["branch", "-r"], in: localPath)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if remoteHasBranches {
                try git.run(["pull", "--quiet", "--ff-only"], in: localPath)
            }
            return
        }

        let existing = (try? fm.contentsOfDirectory(atPath: localPath.path)) ?? []
        guard existing.allSatisfy({ $0 == ".DS_Store" }) else {
            throw RepoSetupError.localPathInUse(localPath)
        }
        log("Cloning into \(localPath.path)…")
        try fm.createDirectory(at: localPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try git.run(["clone", "--quiet", remoteURL.absoluteString, localPath.path])
    }

    private func resolves(_ ref: String) -> Bool {
        (try? git.run(["rev-parse", "--verify", "--quiet", ref], in: localPath)) != nil
    }

    private func ensureIdentity() throws {
        if (try? git.run(["config", "user.name"], in: localPath)) == nil {
            try git.run(["config", "user.name", fallbackIdentity.name], in: localPath)
        }
        if (try? git.run(["config", "user.email"], in: localPath)) == nil {
            try git.run(["config", "user.email", fallbackIdentity.email], in: localPath)
        }
    }

    static func sameRemote(_ a: String, _ b: String) -> Bool {
        func normalize(_ s: String) -> String {
            var s = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while s.hasSuffix("/") { s.removeLast() }
            if s.hasSuffix(".git") { s.removeLast(4) }
            return s
        }
        return normalize(a) == normalize(b)
    }
}
