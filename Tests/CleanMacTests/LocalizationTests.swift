import XCTest
@testable import CleanMac

/// Checks the string catalog: every key has a Turkish translation whose format specifiers match the English key.
final class LocalizationTests: XCTestCase {
    private var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
    }

    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    /// Format specifiers as (argument position, conversion), ignoring "%%".
    private func specifiers(_ s: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDuUxXoOfeEgGcCsSpaAi])|%%"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var result: [String] = []
        var index = 0
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let whole = String(s[Range(m.range, in: s)!])
            if whole == "%%" { continue }
            index += 1
            let position = Range(m.range(at: 1), in: s).map { Int(s[$0])! } ?? index
            let length = whole.contains("ll") ? "ll" : whole.contains("l") ? "l" : ""
            result.append("\(position):\(length)\(s[Range(m.range(at: 2), in: s)!])")
        }
        return result.sorted()
    }

    func testEveryKeyHasTurkishTranslation() throws {
        var missing: [String] = []
        for (key, entry) in try catalog() {
            if entry["extractionState"] as? String == "stale" { continue }
            let localizations = entry["localizations"] as? [String: Any]
            let tr = (localizations?["tr"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let value = tr?["value"] as? String, tr?["state"] as? String == "translated" else {
                missing.append(key); continue
            }
            XCTAssertEqual(specifiers(key), specifiers(value), "Format specifiers differ for \"\(key)\"")
        }
        XCTAssertTrue(missing.isEmpty, "Missing Turkish translations: \(missing.sorted())")
    }

    func testLanguageNamesAreShownInTheirOwnLanguage() {
        XCTAssertEqual(AppLanguage.english.title, "English")
        XCTAssertEqual(AppLanguage.turkish.title, "Türkçe")
        XCTAssertEqual(AppLanguage.fallback, .english)
    }
}
