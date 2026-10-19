import Foundation

/// Commits im's own changes in the memory repository and syncs them with GitHub.
public struct RepoSync: Sendable {
    public let repository: URL
    public let git: Git
    public let identity: GitIdentity

    public init(repository: URL, git: Git, identity: GitIdentity) {
        self.repository = repository
        self.git = git
        self.identity = identity
    }

    /// Commits changes under `paths`, rebases onto the remote and pushes. Blocks; call off the main thread.
    /// - Returns: Whether a commit was made.
    @discardableResult
    public func commitAndSync(_ paths: [String], message: String) throws -> Bool {
        let existing = paths.filter { FileManager.default.fileExists(atPath: repository.appendingPathComponent($0).path) }
        var committed = false
        if !existing.isEmpty {
            try git.run(["add", "-A", "--"] + existing, in: repository)
            let staged = try git.run(["diff", "--cached", "--name-only"], in: repository)
            if !staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try git.ensureIdentity(in: repository, fallback: identity)
                try git.run(["commit", "--quiet", "-m", message], in: repository)
                committed = true
            }
        }
        // Other machines may have pushed in the meantime; edits not ours to commit are stashed and restored.
        try git.run(["pull", "--quiet", "--rebase", "--autostash"], in: repository)
        let ahead = try git.run(["rev-list", "--count", "@{upstream}..HEAD"], in: repository)
        if Int(ahead.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 > 0 {
            try git.run(["push", "--quiet"], in: repository)
        }
        return committed
    }
}
