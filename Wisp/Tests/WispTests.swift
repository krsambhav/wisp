import XCTest
@testable import Wisp

final class UnreadTitleParserTests: XCTestCase {
    func testParsesCount() {
        XCTAssertEqual(UnreadTitleParser.unreadCount(from: "(3) WhatsApp"), 3)
        XCTAssertEqual(UnreadTitleParser.unreadCount(from: "(12) WhatsApp"), 12)
    }
    func testNoCount() {
        XCTAssertEqual(UnreadTitleParser.unreadCount(from: "WhatsApp"), 0)
        XCTAssertEqual(UnreadTitleParser.unreadCount(from: nil), 0)
        XCTAssertEqual(UnreadTitleParser.unreadCount(from: "• WhatsApp"), 0)
    }
}

final class NotificationDeduperTests: XCTestCase {
    func testSuppressesDuplicatesWithinWindow() {
        var d = NotificationDeduper(window: 4)
        let t0 = Date()
        let key = NotificationDeduper.key(accountID: UUID(), title: "A", body: "hi", tag: "chat1")
        XCTAssertTrue(d.shouldShow(key: key, now: t0))
        XCTAssertFalse(d.shouldShow(key: key, now: t0.addingTimeInterval(1)))
        XCTAssertTrue(d.shouldShow(key: key, now: t0.addingTimeInterval(5)))
    }
}

final class HexColorTests: XCTestCase {
    func testRoundTrip() {
        let c = HexColor(hex: "#1DAA61")!
        XCTAssertEqual(c.hexString, "#1DAA61")
        XCTAssertEqual(c.rgbTriplet, "29, 170, 97")
        XCTAssertEqual(HexColor(hex: "#00000080")!.css, "rgba(0, 0, 0, 0.502)")
        XCTAssertNil(HexColor(hex: "nope"))
    }
    func testHSLRoundTrip() {
        let c = HexColor(hex: "#2563EB")!
        let l = c.lightness(c.hsl.l)
        XCTAssertEqual(l.hexString, "#2563EB")
    }
    func testCodable() throws {
        let data = try JSONEncoder().encode(HexColor("#ABCDEF"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"#ABCDEF\"")
        XCTAssertEqual(try JSONDecoder().decode(HexColor.self, from: data), HexColor("#ABCDEF"))
    }
}

final class CSSGeneratorTests: XCTestCase {
    func testTokensContainOverrides() {
        let css = CSSGenerator.tokensCSS(theme: ThemeCatalog.minimal, appearance: AppearanceSettings())
        XCTAssertTrue(css.contains("--WDS-accent: #18181B !important"))
        XCTAssertTrue(css.contains("body.dark"))
        XCTAssertTrue(css.contains("--wisp-bubble-radius: 14px"))
        XCTAssertNil(CSSGenerator.validate(css: css))
    }
    func testAccentOverrideDerivesVariants() {
        var a = AppearanceSettings(); a.accentOverride = HexColor("#2563EB")
        let p = CSSGenerator.resolved(ThemeCatalog.defaultTheme.light, appearance: a)
        XCTAssertEqual(p.accent, HexColor("#2563EB"))
        XCTAssertNotEqual(p.accentEmphasized, p.accent)
        XCTAssertEqual(p.onAccent, HexColor("#FFFFFF"))
    }
    func testValidation() {
        XCTAssertNil(CSSGenerator.validate(css: "a { color: red; } /* { */ b { x: '}' }"))
        XCTAssertNotNil(CSSGenerator.validate(css: "a { color: red;"))
        XCTAssertNotNil(CSSGenerator.validate(css: "a { } }"))
    }
    func testAllThemesProduceValidCSS() {
        for t in ThemeCatalog.all {
            for mode in [AppearanceMode.light, .dark] {
                var a = AppearanceSettings(); a.mode = mode; a.themeID = t.id
                XCTAssertNil(CSSGenerator.validate(css: CSSGenerator.tokensCSS(theme: t, appearance: a)), t.id)
            }
        }
    }
}

final class CustomScriptTests: XCTestCase {
    func testHeaderRoundTrip() {
        let s = CustomScript(name: "Test", summary: "desc", enabled: false, injectionTime: .documentStart, world: .page, source: "wisp.log('x');\n")
        let parsed = CustomScript.parse(fileContents: s.fileContents, id: s.id, fallbackName: "fallback", dates: (Date(), Date()))
        XCTAssertEqual(parsed.name, "Test")
        XCTAssertEqual(parsed.summary, "desc")
        XCTAssertFalse(parsed.enabled)
        XCTAssertEqual(parsed.injectionTime, .documentStart)
        XCTAssertEqual(parsed.world, .page)
        XCTAssertEqual(parsed.source, "wisp.log('x');\n")
    }
    func testPlainFileWithoutHeader() {
        let parsed = CustomScript.parse(fileContents: "console.log(1)", id: UUID(), fallbackName: "plain", dates: (Date(), Date()))
        XCTAssertEqual(parsed.name, "plain")
        XCTAssertEqual(parsed.source, "console.log(1)")
        XCTAssertEqual(parsed.world, .isolated)
    }
    func testSyntaxCheck() {
        XCTAssertNil(CustomScript.checkSyntax("const a = 1; function f() { return a }"))
        let err = CustomScript.checkSyntax("const a = ;")
        XCTAssertNotNil(err)
    }
    func testWrapperIsolatesErrors() {
        let s = CustomScript(name: "Bad 'quote'", source: "throw new Error('boom')")
        let wrapped = InjectionEngine.wrap(script: s)
        XCTAssertTrue(wrapped.contains("'Bad \\'quote\\''"))
        XCTAssertNil(CustomScript.checkSyntax(wrapped))
    }
}

final class PresetIOTests: XCTestCase {
    func testRoundTrip() throws {
        let p = CustomizationPreset(name: "P", exportedAt: Date(), appearance: AppearanceSettings(), customCSS: "a{}", scripts: nil)
        let decoded = try PresetIO.decode(try PresetIO.encode(p))
        XCTAssertEqual(decoded.name, "P")
        XCTAssertEqual(decoded.customCSS, "a{}")
    }
    func testRejectsForeignJSON() {
        XCTAssertThrowsError(try PresetIO.decode(Data("{\"format\":\"other\",\"version\":1,\"name\":\"x\",\"exportedAt\":\"2026-01-01T00:00:00Z\",\"appearance\":{},\"customCSS\":\"\"}".utf8)))
    }
}

final class UserAgentTests: XCTestCase {
    func testSuffixShape() {
        let s = UserAgent.applicationNameSuffix()
        XCTAssertTrue(s.hasPrefix("Version/"))
        XCTAssertTrue(s.contains("Safari/605.1.15"))
    }
}

final class JSLiteralTests: XCTestCase {
    func testEscapes() {
        XCTAssertEqual("a'b\\c\nd".jsStringLiteral, "'a\\'b\\\\c\\nd'")
    }
}

final class CSSValidatorEdgeCaseTests: XCTestCase {
    func testEscapedBackslashInString() {
        XCTAssertNil(CSSGenerator.validate(css: #"a::before { content: "foo\\"; } b { color: red; }"#))
    }
    func testShortCommentIsNotClosedEarly() {
        XCTAssertNotNil(CSSGenerator.validate(css: "/*/ a { }"))
        XCTAssertNil(CSSGenerator.validate(css: "/**/ a { }"))
    }
}
