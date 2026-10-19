import XCTest
@testable import IMCore

final class CatSkinTests: XCTestCase {
    func testBuiltinCats() {
        XCTAssertEqual(BuiltinCats.all.map(\.id), ["calico", "blue", "orange", "ragdoll", "american-shorthair"])
        XCTAssertEqual(BuiltinCats.defaultID, "calico")
        for cat in BuiltinCats.all {
            XCTAssertNotNil(cat.blink, cat.id)
            XCTAssertLessThanOrEqual(cat.height + 1, CatSkin.maxHeight, cat.id)
        }
    }

    func testParsesColorsAndDefaultsNameToID() throws {
        let cat = try CatSkin(id: "tiny", json: json(palette: ["k": "#FF000080"], awake: ["k."]))

        XCTAssertEqual(cat.name, "tiny")
        XCTAssertEqual(cat.palette["k"], CatSkin.Color(red: 1, green: 0, blue: 0, alpha: 128.0 / 255))
        XCTAssertNil(cat.blink)
    }

    func testRejectsInvalidCats() {
        assertError(json(palette: ["k": "#000"], awake: ["k"]), .invalidColor(key: "k", value: "#000"))
        assertError(json(palette: ["kk": "#000000"], awake: ["k"]), .invalidPaletteKey("kk"))
        assertError(json(palette: ["k": "#000000"], awake: ["kx"]), .unknownPixel("x", frame: "awake"))
        assertError(json(palette: ["k": "#000000"], awake: ["kk", "k"]), .unevenRows(frame: "awake"))
        assertError(json(palette: ["k": "#000000"], awake: ["k"], blink: ["kk"]), .frameSizeMismatch(frame: "blink"))
        assertError(json(palette: ["k": "#000000"], awake: [String(repeating: "k", count: 30)]), .tooLarge(width: 30, height: 1))
        assertError(json(palette: ["k": "#000000"], awake: []), .empty)
        XCTAssertThrowsError(try CatSkin(id: "x", json: Data("{\"palette\": {}}".utf8))) { error in
            XCTAssertEqual(error.localizedDescription, "not valid cat JSON (missing \"awake\")")
        }
    }

    private func assertError(_ data: Data, _ expected: CatSkinError, line: UInt = #line) {
        XCTAssertThrowsError(try CatSkin(id: "x", json: data), line: line) { error in
            XCTAssertEqual(error as? CatSkinError, expected, line: line)
        }
    }
}

final class CatLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLoadsCustomCatsOverridesAndProblems() throws {
        try json(name: "Zebra", palette: ["k": "#000000"], awake: ["k"]).write(to: root.appendingPathComponent("zebra.json"))
        try json(name: "Mochi", palette: ["k": "#000000"], awake: ["k"]).write(to: root.appendingPathComponent("mochi.json"))
        try json(name: "My Orange", palette: ["k": "#000000"], awake: ["k"]).write(to: root.appendingPathComponent("orange.json"))
        try Data("{".utf8).write(to: root.appendingPathComponent("broken.json"))
        try Data("notes".utf8).write(to: root.appendingPathComponent("README.md"))

        let library = CatLibrary.load(from: root)

        XCTAssertEqual(library.builtins.map(\.id), BuiltinCats.all.map(\.id))
        XCTAssertEqual(library.cat(id: "orange")?.name, "My Orange")
        XCTAssertEqual(library.custom.map(\.name), ["Mochi", "Zebra"])
        XCTAssertEqual(library.problems.map(\.file), ["broken.json"])
    }

    func testResolveFallsBackToDefault() {
        let library = CatLibrary.builtinOnly
        XCTAssertEqual(library.resolve("ragdoll").id, "ragdoll")
        XCTAssertEqual(library.resolve("no-such-cat").id, "calico")
        XCTAssertEqual(library.resolve(nil).id, "calico")
    }

    func testPrepareDirectoryWritesReadmeOnce() throws {
        let cats = root.appendingPathComponent("cats")
        try CatLibrary.prepareDirectory(cats)
        let readme = cats.appendingPathComponent("README.md")
        XCTAssertTrue(try String(contentsOf: readme, encoding: .utf8).contains("\"name\": \"Calico\""))

        try Data("mine".utf8).write(to: readme)
        try CatLibrary.prepareDirectory(cats)
        XCTAssertEqual(try String(contentsOf: readme, encoding: .utf8), "mine")
    }

    func testConfigKeepsOtherKeys() throws {
        let config = root.appendingPathComponent("config.json")
        XCTAssertNil(IMConfig.catID(at: config))
        try Data(#"{"future": 1}"#.utf8).write(to: config)

        try IMConfig.setCatID("ragdoll", at: config)

        XCTAssertEqual(IMConfig.catID(at: config), "ragdoll")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertEqual(object?["future"] as? Int, 1)
    }
}

private func json(name: String? = nil, palette: [String: String], awake: [String], blink: [String]? = nil) -> Data {
    var object: [String: Any] = ["palette": palette, "awake": awake]
    object["name"] = name
    object["blink"] = blink
    return try! JSONSerialization.data(withJSONObject: object)
}
