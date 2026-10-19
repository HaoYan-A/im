import XCTest
@testable import IMCore

final class RepoScaffoldTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreatesLayoutInEmptyDirectory() throws {
        let created = try RepoScaffold.apply(at: root)

        XCTAssertEqual(Set(created), [
            "README.md",
            "mcp/.gitkeep",
            "skills/.gitkeep",
            "memory/index.md",
            "memory/personal/.gitkeep",
            "memory/project/.gitkeep",
        ])
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("Keep this repository private"))
    }

    func testNeverOverwritesExistingContent() throws {
        try write("README.md", "mine")
        try write("mcp/github.json", "{}")

        let created = try RepoScaffold.apply(at: root)

        XCTAssertEqual(try read("README.md"), "mine")
        XCTAssertFalse(created.contains("README.md"))
        XCTAssertFalse(created.contains("mcp/.gitkeep"))
        XCTAssertTrue(created.contains("memory/index.md"))
    }

    func testIsIdempotent() throws {
        try RepoScaffold.apply(at: root)
        XCTAssertEqual(try RepoScaffold.apply(at: root), [])
    }

    private func write(_ path: String, _ contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

/// Exercises the real git flow against a local bare repository standing in for GitHub.
final class RepoSetupTests: XCTestCase {
    private var root: URL!
    private var remote: URL!
    // Ignore the developer's own git config so the fallback identity is exercised.
    private let git = Git(environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        remote = root.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try git.run(["init", "--quiet", "--bare", remote.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func setup(clone: String = "clone") -> RepoSetup {
        RepoSetup(
            remoteURL: remote,
            localPath: root.appendingPathComponent(clone),
            defaultBranch: "main",
            git: git,
            fallbackIdentity: .init(name: "im test", email: "test@example.com")
        )
    }

    func testInitializesEmptyRemote() throws {
        let result = try setup().run()

        XCTAssertTrue(result.pushed)
        let files = try git.run(["--git-dir", remote.path, "ls-tree", "-r", "--name-only", "main"])
        XCTAssertEqual(Set(files.split(separator: "\n").map(String.init)), Set(result.created))
        let author = try git.run(["--git-dir", remote.path, "log", "-1", "--format=%an <%ae>", "main"])
        XCTAssertEqual(author.trimmingCharacters(in: .whitespacesAndNewlines), "im test <test@example.com>")
    }

    func testReconnectingDoesNothingNew() throws {
        try setup().run()
        // Same clone again, then a fresh clone on "another machine".
        XCTAssertFalse(try setup().run().pushed)
        XCTAssertFalse(try setup(clone: "other-machine").run().pushed)
    }

    func testRefusesUnrelatedLocalDirectory() throws {
        let local = root.appendingPathComponent("clone")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try "notes".write(to: local.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try setup().run()) { error in
            guard case RepoSetupError.localPathInUse = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testSameRemoteIgnoresGitSuffixAndCase() {
        XCTAssertTrue(RepoSetup.sameRemote("https://github.com/Octo/Mem.git\n", "https://github.com/octo/mem"))
        XCTAssertFalse(RepoSetup.sameRemote("https://github.com/octo/a.git", "https://github.com/octo/b.git"))
    }
}
