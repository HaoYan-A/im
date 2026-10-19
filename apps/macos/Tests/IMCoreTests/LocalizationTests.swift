import XCTest
@testable import IMCore

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Language.current = .default
    }

    func testDefaultsToEnglish() {
        XCTAssertEqual(Language.default, .english)
        XCTAssertEqual(L("Cat", "小猫"), "Cat")
    }

    func testSwitchesLanguage() {
        Language.current = .chinese
        XCTAssertEqual(L("Cat", "小猫"), "小猫")
        XCTAssertEqual(GitHubError.api(status: 404, message: "Not Found").localizedDescription, "GitHub API 错误 404：Not Found")
    }

    func testCatNames() throws {
        let ragdoll = try XCTUnwrap(BuiltinCats.all.first { $0.id == "ragdoll" })
        XCTAssertEqual(ragdoll.localizedName, "Ragdoll")
        Language.current = .chinese
        XCTAssertEqual(ragdoll.localizedName, "布偶")
        XCTAssertEqual(BuiltinCats.all.map(\.localizedName), ["三花", "蓝猫", "橘猫", "布偶", "美短"])

        // Custom cats without a translation keep their name.
        let custom = try CatSkin(id: "mochi", json: Data(##"{"name": "Mochi", "palette": {"k": "#000000"}, "awake": ["k"]}"##.utf8))
        XCTAssertEqual(custom.localizedName, "Mochi")
    }

    func testLanguageConfig() throws {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: config) }

        XCTAssertEqual(IMConfig.language(at: config), .english)
        try IMConfig.setCatID("blue", at: config)
        try IMConfig.setLanguage(.chinese, at: config)
        XCTAssertEqual(IMConfig.language(at: config), .chinese)
        XCTAssertEqual(IMConfig.catID(at: config), "blue")

        try Data(#"{"language": "fr"}"#.utf8).write(to: config)
        XCTAssertEqual(IMConfig.language(at: config), .english)
    }
}
