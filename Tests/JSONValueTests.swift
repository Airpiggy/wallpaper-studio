import XCTest
@testable import WallpaperStudio

final class JSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testCoercesNumberFromString() throws {
        // WE frequently stores numbers as strings.
        let v = try decode("\"42\"")
        XCTAssertEqual(v.doubleValue, 42)
        XCTAssertEqual(v.stringValue, "42")
    }

    func testBoolCoercion() throws {
        XCTAssertEqual(try decode("true").boolValue, true)
        XCTAssertEqual(try decode("\"false\"").boolValue, false)
        XCTAssertEqual(try decode("1").boolValue, true)
    }

    func testObjectAndArray() throws {
        let v = try decode("{\"a\": 1, \"b\": [true, \"x\"]}")
        XCTAssertEqual(v.objectValue?["a"]?.doubleValue, 1)
        XCTAssertEqual(v.objectValue?["b"]?.arrayValue?.count, 2)
    }
}
