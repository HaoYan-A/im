import XCTest
@testable import IMCore

/// An in-memory GitHub: the HEAD of each repository plus every folder version ever served.
private final class FakeUpstream: SkillUpstream, @unchecked Sendable {
    private var heads: [String: [String: String]] = [:]
    private var folders: [String: [String: String]] = [:]
    private var contents: [String: Data] = [:]

    /// Replaces the repository's HEAD with these files (path → text).
    func publish(_ repository: String, _ files: [String: String]) {
        heads[repository] = files
        _ = headTree(repository)
    }

    func tree(_ repository: String, ref: String) async throws -> GitTree {
        if ref == "HEAD", heads[repository] != nil { return headTree(repository) }
        guard let blobs = folders[ref] else { throw GitHubError.api(status: 404, message: "Not Found") }
        return GitTree(sha: ref, tree: blobs.map { .init(path: $0.key, type: "blob", sha: $0.value) })
    }

    func blob(_ repository: String, sha: String) async throws -> Data {
        guard let data = contents[sha] else { throw GitHubError.api(status: 404, message: "Not Found") }
        return data
    }

    private func headTree(_ repository: String) -> GitTree {
        var entries: [GitTree.Entry] = []
        var blobsByFolder: [String: [String: String]] = [:]
        for (path, text) in heads[repository] ?? [:] {
            let data = Data(text.utf8)
            let sha = SkillBlobs.gitBlobSHA(data)
            contents[sha] = data
            entries.append(.init(path: path, type: "blob", sha: sha))
            var parts = path.split(separator: "/").map(String.init)
            var relative = [parts.removeLast()]
            while !parts.isEmpty {
                blobsByFolder[parts.joined(separator: "/"), default: [:]][relative.joined(separator: "/")] = sha
                relative.insert(parts.removeLast(), at: 0)
            }
        }
        for (folder, blobs) in blobsByFolder {
            // Stand-in for git's tree hash: anything that changes exactly when the contents do.
            let sha = blobs.keys.sorted().map { "\($0)=\(blobs[$0]!)" }.joined(separator: ";").sha256
            folders[sha] = blobs
            entries.append(.init(path: folder, type: "tree", sha: sha))
        }
        return GitTree(sha: "head", tree: entries)
    }
}

private struct FakeHub: SkillHubSearching {
    let results: [SkillHubResult]
    func search(_ query: String, limit: Int) async throws -> [SkillHubResult] { results }
}

final class SkillSourceTests: XCTestCase {
    private var root: URL!
    private var environment: SkillEnvironment!
    private let upstream = FakeUpstream()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        environment = SkillEnvironment(home: root.appendingPathComponent("home"), repository: root.appendingPathComponent("repo"), backups: root.appendingPathComponent("backup"))
        try FileManager.default.createDirectory(at: environment.repositorySkills, withIntermediateDirectories: true)
        upstream.publish("matt/skills", ["skills/productivity/grill-me/SKILL.md": "v1", "README.md": "repo"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBlobSHAMatchesGit() {
        // `printf 'hello\n' | git hash-object --stdin`
        XCTAssertEqual(SkillBlobs.gitBlobSHA(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testBlobsKeepNestedPaths() throws {
        // Through the /var symlink on purpose: the bug only showed when the two spellings mixed.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("agents"), withIntermediateDirectories: true)
        try "a".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "b".write(to: folder.appendingPathComponent("agents/openai.yaml"), atomically: true, encoding: .utf8)

        XCTAssertEqual(Set(SkillBlobs.of(folder).keys), ["SKILL.md", "agents/openai.yaml"])
        XCTAssertEqual(Set(SkillScanner.content(of: folder).files.keys), ["SKILL.md", "agents/openai.yaml"])
    }

    func testReadsSkillsCLILockFile() throws {
        let lock = environment.home.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"""
        {"version": 3, "skills": {
          "grill-me": {"source": "matt/skills", "sourceType": "github", "skillPath": "skills/productivity/grill-me/SKILL.md", "skillFolderHash": "abc"},
          "docs": {"source": "mintlify.com", "sourceType": "well-known", "skillPath": "docs/SKILL.md", "skillFolderHash": "def"}
        }}
        """#.utf8).write(to: lock)

        XCTAssertEqual(SkillSource.fromSkillsLockFile(home: environment.home), [
            "grill-me": SkillSource(repository: "matt/skills", path: "skills/productivity/grill-me", treeSHA: "abc"),
        ])
    }

    // MARK: Install

    func testInstallDownloadsLinksAndRecordsSource() async throws {
        let source = try await installer.install(result, agents: [.claudeCode, .codex])

        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "v1")
        XCTAssertEqual(source.path, "skills/productivity/grill-me")
        XCTAssertEqual(SkillManifest.load(environment).skills["grill-me"]?.source, source)
        let skill = try XCTUnwrap(SkillScanner.scan(environment).first)
        XCTAssertEqual(skill.state, .linked)
        XCTAssertEqual(skill.linkedAgents, [.claudeCode, .codex])
    }

    func testInstallRefusesNameClash() async throws {
        let claude = environment.home.appendingPathComponent(".claude/skills/grill-me")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try "mine".write(to: claude.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        do {
            try await installer.install(result, agents: [.codex])
            XCTFail("expected a name clash")
        } catch SkillError.nameTaken {}
    }

    // MARK: Updates

    func testUpdatesUntouchedSkillAndBacksUpOldVersion() async throws {
        try await installer.install(result, agents: [.claudeCode])
        upstream.publish("matt/skills", ["skills/productivity/grill-me/SKILL.md": "v2", "skills/productivity/grill-me/extra.md": "new"])

        let statuses = await updater.run()

        XCTAssertEqual(statuses, ["grill-me": .updated])
        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "v2")
        XCTAssertEqual(try text("skills/grill-me/extra.md"), "new")
        // The agent link still works: it points at the folder, not the old files.
        XCTAssertEqual(try String(contentsOf: environment.home.appendingPathComponent(".claude/skills/grill-me/SKILL.md"), encoding: .utf8), "v2")
        let rerun = await updater.run()
        XCTAssertEqual(rerun, ["grill-me": .upToDate])
        XCTAssertTrue(FileManager.default.fileExists(atPath: environment.backups.path))
    }

    func testKeepsLocalEditsUnlessForced() async throws {
        try await installer.install(result, agents: [.claudeCode])
        try "my tweak".write(to: environment.repositorySkill("grill-me").appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        upstream.publish("matt/skills", ["skills/productivity/grill-me/SKILL.md": "v2"])

        let statuses = await updater.run()

        XCTAssertEqual(statuses, ["grill-me": .editedLocally])
        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "my tweak")

        let forced = await updater.run(force: ["grill-me"])

        XCTAssertEqual(forced, ["grill-me": .updated])
        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "v2")
    }

    func testReportsSkillRemovedUpstream() async throws {
        try await installer.install(result, agents: [.claudeCode])
        upstream.publish("matt/skills", ["README.md": "gone"])

        let statuses = await updater.run()

        XCTAssertEqual(statuses, ["grill-me": .missingUpstream])
        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "v1")
    }

    func testLinkingPicksUpLockFileSource() throws {
        let skill = environment.home.appendingPathComponent(".agents/skills/grill-me")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "v1".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try Data(#"{"version":3,"skills":{"grill-me":{"source":"matt/skills","sourceType":"github","skillPath":"skills/productivity/grill-me/SKILL.md","skillFolderHash":"t1"}}}"#.utf8)
            .write(to: environment.home.appendingPathComponent(".agents/.skill-lock.json"))

        let found = try XCTUnwrap(SkillScanner.scan(environment).first)
        try SkillLinker(environment: environment).apply([SkillChange(skill: found, action: .link(version: found.versions[0].id, agents: [.codex]))])

        XCTAssertEqual(SkillManifest.load(environment).skills["grill-me"]?.source?.repository, "matt/skills")
    }

    // MARK: Finding sources

    func testFindsMatchingSourceFirst() async throws {
        upstream.publish("fork/skills", ["grill-me/SKILL.md": "forked"])
        let local = root.appendingPathComponent("local/grill-me")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try "v1".write(to: local.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let hub = FakeHub(results: [
            SkillHubResult(id: "fork/skills/grill-me", source: "fork/skills", skillId: "grill-me", name: "grill-me", installs: 9_000),
            result,
            SkillHubResult(id: "matt/skills/grill-me-lite", source: "matt/skills", skillId: "grill-me-lite", name: "grill-me-lite", installs: 1),
        ])

        let candidates = try await SkillSourceFinder(upstream: upstream, hub: hub).candidates(for: "grill-me", localFolder: local)

        XCTAssertEqual(candidates.map(\.source.repository), ["matt/skills", "fork/skills"])
        XCTAssertEqual(candidates.map(\.matchesLocal), [true, false])
    }

    func testAdoptingDifferentSourceReplacesLocalCopy() async throws {
        try makeLinkedSkill("grill-me", text: "old local")
        let hub = FakeHub(results: [result])
        let candidates = try await SkillSourceFinder(upstream: upstream, hub: hub)
            .candidates(for: "grill-me", localFolder: environment.repositorySkill("grill-me"))
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertFalse(candidate.matchesLocal)

        try await updater.adopt("grill-me", candidate: candidate)

        XCTAssertEqual(try text("skills/grill-me/SKILL.md"), "v1")
        XCTAssertEqual(SkillManifest.load(environment).skills["grill-me"]?.source?.repository, "matt/skills")
        let statuses = await updater.run()
        XCTAssertEqual(statuses, ["grill-me": .upToDate])
    }

    // MARK: Helpers

    private var result: SkillHubResult {
        SkillHubResult(id: "matt/skills/grill-me", source: "matt/skills", skillId: "grill-me", name: "grill-me", installs: 1_000)
    }

    private var installer: SkillInstaller { SkillInstaller(environment: environment, upstream: upstream) }
    private var updater: SkillUpdater { SkillUpdater(environment: environment, upstream: upstream) }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: environment.repository.appendingPathComponent(path), encoding: .utf8)
    }

    private func makeLinkedSkill(_ name: String, text: String) throws {
        let folder = environment.repositorySkill(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try SkillLinker(environment: environment).installLinks(name, into: [.claudeCode])
    }
}
