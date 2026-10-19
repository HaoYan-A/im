import XCTest
@testable import IMCore

/// Runs scanning and linking against a fake home folder and memory repository.
final class SkillTests: XCTestCase {
    private var root: URL!
    private var environment: SkillEnvironment!
    private var claude: URL { environment.home.appendingPathComponent(".claude/skills") }
    private var codex: URL { environment.home.appendingPathComponent(".agents/skills") }
    private var codexLegacy: URL { environment.home.appendingPathComponent(".codex/skills") }

    override func setUpWithError() throws {
        // Resolve /var → /private/var up front (only works once the folder exists) so paths compare the way the scanner sees them.
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        environment = SkillEnvironment(
            home: root.appendingPathComponent("home"),
            repository: root.appendingPathComponent("repo"),
            backups: root.appendingPathComponent("backup")
        )
        try FileManager.default.createDirectory(at: environment.repositorySkills, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Scanning

    func testScanFindsSkillsAndIgnoresNoise() throws {
        try makeSkill("review", in: claude, description: "\"Review a diff\"")
        try makeSkill("deploy", in: codex)
        try makeSkill("old-tool", in: codexLegacy)
        try makeSkill("imagegen", in: codexLegacy.appendingPathComponent(".system"))
        try makeSkill("hidden", in: claude.appendingPathComponent(".trash"))
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("not-a-skill"), withIntermediateDirectories: true)

        let skills = SkillScanner.scan(environment)

        XCTAssertEqual(skills.map(\.name), ["deploy", "old-tool", "review"])
        XCTAssertEqual(skill("review", in: skills).description, "Review a diff")
        XCTAssertEqual(skill("old-tool", in: skills).installedAgents, [.codex])
        XCTAssertEqual(skills.map(\.state), [.notLinked, .notLinked, .notLinked])
    }

    func testIdenticalCopiesMergeAndDifferentCopiesConflict() throws {
        try makeSkill("same", in: claude, body: "A")
        try makeSkill("same", in: codex, body: "A")
        try makeSkill("diverged", in: claude, body: "old")
        try makeSkill("diverged", in: codex, body: "new", extraFile: "notes.md")
        // A symlink to another agent's copy is the same skill, not a second version.
        try makeSkill("shared", in: codex)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: claude.appendingPathComponent("shared"), withDestinationURL: codex.appendingPathComponent("shared"))

        let skills = SkillScanner.scan(environment)

        XCTAssertEqual(skill("same", in: skills).state, .notLinked)
        XCTAssertEqual(skill("shared", in: skills).state, .notLinked)
        XCTAssertEqual(skill("shared", in: skills).installedAgents, [.claudeCode, .codex])
        let diverged = skill("diverged", in: skills)
        XCTAssertEqual(diverged.state, .differentVersions)
        XCTAssertEqual(diverged.versions.count, 2)
        XCTAssertEqual(diverged.differingFiles, ["SKILL.md", "notes.md"])
    }

    // MARK: Linking

    func testLinkMovesSkillIntoIMAndLinksEveryAgent() throws {
        try makeSkill("review", in: claude, body: "v1")
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("review/.git"), withIntermediateDirectories: true)

        try link("review", agents: [.claudeCode, .codex])

        let review = skill("review", in: SkillScanner.scan(environment))
        XCTAssertEqual(review.state, .linked)
        XCTAssertEqual(review.linkedAgents, [.claudeCode, .codex])
        XCTAssertEqual(try body(environment.repositorySkill("review")), "v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.repositorySkill("review/.git").path))
        // The original folder is kept in the backup, mirroring its place in the home folder.
        XCTAssertEqual(try body(backupFolder().appendingPathComponent(".claude/skills/review")), "v1")
        XCTAssertEqual(SkillManifest.load(environment).agents(for: "review"), [.claudeCode, .codex])
    }

    func testLinkChosenVersionBacksUpTheOther() throws {
        try makeSkill("diverged", in: claude, body: "claude")
        try makeSkill("diverged", in: codex, body: "codex")
        let diverged = skill("diverged", in: SkillScanner.scan(environment))
        let codexVersion = try XCTUnwrap(diverged.versions.first { $0.owners == [.codex] })

        try SkillLinker(environment: environment).apply([
            SkillChange(skill: diverged, action: .link(version: codexVersion.id, agents: [.claudeCode, .codex])),
        ])

        XCTAssertEqual(try body(claude.appendingPathComponent("diverged")), "codex")
        XCTAssertEqual(try body(backupFolder().appendingPathComponent(".claude/skills/diverged")), "claude")
        XCTAssertEqual(skill("diverged", in: SkillScanner.scan(environment)).state, .linked)
    }

    func testLinkOnlyIntoChosenAgents() throws {
        try makeSkill("claude-only", in: claude)

        try link("claude-only", agents: [.claudeCode])

        let linked = skill("claude-only", in: SkillScanner.scan(environment))
        XCTAssertEqual(linked.linkedAgents, [.claudeCode])
        XCTAssertFalse(FileManager.default.fileExists(atPath: codex.appendingPathComponent("claude-only").path))
        XCTAssertEqual(SkillManifest.load(environment).skills["claude-only"]?.agents, [.claudeCode])
    }

    func testSetAgentsAddsAndRemovesLinks() throws {
        try makeSkill("review", in: claude)
        try link("review", agents: [.claudeCode])

        try SkillLinker(environment: environment).apply([
            SkillChange(skill: skill("review", in: SkillScanner.scan(environment)), action: .setAgents([.codex])),
        ])

        let review = skill("review", in: SkillScanner.scan(environment))
        XCTAssertEqual(review.linkedAgents, [.codex])
        XCTAssertFalse(FileManager.default.fileExists(atPath: claude.appendingPathComponent("review").path))
    }

    func testSkillFromAnotherMachineIsInstalledFromIM() throws {
        try makeSkill("from-laptop", in: environment.repositorySkills, body: "shared")
        XCTAssertEqual(skill("from-laptop", in: SkillScanner.scan(environment)).state, .onlyInIM)

        try link("from-laptop", agents: [.codex])

        XCTAssertEqual(skill("from-laptop", in: SkillScanner.scan(environment)).state, .linked)
        XCTAssertEqual(try body(codex.appendingPathComponent("from-laptop")), "shared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.backups.path))
    }

    func testUnlinkRestoresRealFoldersAndKeepsIMCopy() throws {
        try makeSkill("review", in: claude, body: "v1")
        try link("review", agents: [.claudeCode, .codex])

        try SkillLinker(environment: environment).apply([
            SkillChange(skill: skill("review", in: SkillScanner.scan(environment)), action: .unlink),
        ])

        let review = skill("review", in: SkillScanner.scan(environment))
        XCTAssertEqual(review.state, .notLinked)
        XCTAssertEqual(review.linkedAgents, [])
        XCTAssertEqual(review.installedAgents, [.claudeCode, .codex])
        XCTAssertEqual(try body(claude.appendingPathComponent("review")), "v1")
        XCTAssertNotNil(review.repositoryCopy)
    }

    func testUnlinkAllLeavesAgentsWorkingWithoutTheClone() throws {
        try makeSkill("review", in: claude, body: "v1")
        try makeSkill("deploy", in: codex, body: "v2")
        try link("review", agents: [.claudeCode, .codex])
        try link("deploy", agents: [.codex])

        XCTAssertEqual(try SkillLinker(environment: environment).unlinkAll(), 2)
        try FileManager.default.removeItem(at: environment.repository)

        XCTAssertEqual(try body(claude.appendingPathComponent("review")), "v1")
        XCTAssertEqual(try body(codex.appendingPathComponent("review")), "v1")
        XCTAssertEqual(try body(codex.appendingPathComponent("deploy")), "v2")
    }

    func testRefusesToReplaceUnknownFolder() throws {
        try makeSkill("from-laptop", in: environment.repositorySkills)
        // Something without a SKILL.md already sits where the link would go.
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("from-laptop"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try link("from-laptop", agents: [.codex])) { error in
            guard case SkillError.occupied = error else { return XCTFail("unexpected error: \(error)") }
        }
    }

    // MARK: Helpers

    private func makeSkill(_ name: String, in directory: URL, description: String = "Does things", body: String = "body", extraFile: String? = nil) throws {
        let folder = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(description)\n---\n\(body)".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        if let extraFile {
            try "extra".write(to: folder.appendingPathComponent(extraFile), atomically: true, encoding: .utf8)
        }
    }

    private func link(_ name: String, agents: Set<SkillAgent>) throws {
        let skill = skill(name, in: SkillScanner.scan(environment))
        try SkillLinker(environment: environment).apply([
            SkillChange(skill: skill, action: .link(version: skill.versions[0].id, agents: agents)),
        ])
    }

    private func skill(_ name: String, in skills: [Skill]) -> Skill {
        skills.first { $0.name == name }!
    }

    /// The text after the front matter.
    private func body(_ folder: URL) throws -> String {
        let text = try String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)
        return String(text.components(separatedBy: "---\n").last!)
    }

    private func backupFolder() throws -> URL {
        let runs = try FileManager.default.contentsOfDirectory(at: environment.backups, includingPropertiesForKeys: nil)
        return try XCTUnwrap(runs.first)
    }
}

/// `RepoSync` against a local bare repository standing in for GitHub.
final class RepoSyncTests: XCTestCase {
    private let git = Git(environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"])
    private let identity = GitIdentity(name: "im test", email: "test@example.com")

    func testCommitsPullsAndPushes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = root.appendingPathComponent("remote.git")
        try git.run(["init", "--quiet", "--bare", "-b", "main", remote.path])
        let laptop = root.appendingPathComponent("laptop")
        let desktop = root.appendingPathComponent("desktop")
        try RepoSetup(remoteURL: remote, localPath: laptop, defaultBranch: "main", git: git, fallbackIdentity: identity).run()
        try RepoSetup(remoteURL: remote, localPath: desktop, defaultBranch: "main", git: git, fallbackIdentity: identity).run()

        // The laptop adds a skill; the desktop has an unrelated local edit and a skill of its own.
        try "a".write(to: laptop.appendingPathComponent("skills/a.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try RepoSync(repository: laptop, git: git, identity: identity).commitAndSync(["skills"], message: "add a"))
        try "b".write(to: desktop.appendingPathComponent("skills/b.md"), atomically: true, encoding: .utf8)
        try "note".write(to: desktop.appendingPathComponent("memory/index.md"), atomically: true, encoding: .utf8)
        try RepoSync(repository: desktop, git: git, identity: identity).commitAndSync(["skills", ".im"], message: "add b")

        let files = try git.run(["--git-dir", remote.path, "ls-tree", "-r", "--name-only", "main"])
        XCTAssertTrue(files.contains("skills/a.md"))
        XCTAssertTrue(files.contains("skills/b.md"))
        // Not ours to commit: still a local edit on the desktop.
        XCTAssertEqual(try String(contentsOf: desktop.appendingPathComponent("memory/index.md"), encoding: .utf8), "note")
        XCTAssertFalse(try RepoSync(repository: laptop, git: git, identity: identity).commitAndSync(["skills"], message: "noop"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: laptop.appendingPathComponent("skills/b.md").path))
    }
}
