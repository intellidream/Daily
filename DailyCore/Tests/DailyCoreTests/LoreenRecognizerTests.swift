import XCTest
import CoreText
@testable import DailyCore

final class LoreenRecognizerTests: XCTestCase {

    func testFontRegistrationAndCmapCoverage() {
        XCTAssertTrue(LoreenFontRegistry.registerIfNeeded(), "Loreen-Regular.ttf should register via CoreText")

        let ctFont = CTFontCreateWithName(LoreenFontRegistry.postScriptName as CFString, 24, nil)
        let psName = CTFontCopyPostScriptName(ctFont) as String
        XCTAssertEqual(psName, LoreenFontRegistry.postScriptName)

        // Verify uppercase, lowercase, Romanian diacritics, digits, and TagDoS DSL chars map to valid glyphs (> 0)
        let samples: [UniChar] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzĂăÂâÎîȘșŞşȚțŢţ0123456789/&$€!?:;-".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: samples.count)
        let mapped = CTFontGetGlyphsForCharacters(ctFont, samples, &glyphs, samples.count)
        XCTAssertTrue(mapped, "All Latin, Romanian diacritics, digits, and DSL punctuation should map in Loreen-Regular.ttf")
        for (idx, g) in glyphs.enumerated() {
            XCTAssertNotEqual(g, 0, "Character at index \(idx) mapped to .notdef")
        }

        // Verify monocase + Romanian diacritics map to the exact same glyph IDs as A, I, S, T
        let eqPairs: [(Character, Character)] = [
            ("A", "a"), ("A", "Ă"), ("A", "ă"), ("A", "Â"), ("A", "â"),
            ("I", "i"), ("I", "Î"), ("I", "î"),
            ("S", "s"), ("S", "Ș"), ("S", "ș"),
            ("T", "t"), ("T", "Ț"), ("T", "ț")
        ]
        for (base, variant) in eqPairs {
            var u1 = Array(String(base).utf16)
            var u2 = Array(String(variant).utf16)
            var g1: [CGGlyph] = [0]
            var g2: [CGGlyph] = [0]
            CTFontGetGlyphsForCharacters(ctFont, &u1, &g1, 1)
            CTFontGetGlyphsForCharacters(ctFont, &u2, &g2, 1)
            XCTAssertEqual(g1[0], g2[0], "\(variant) should map to same glyph as \(base)")
        }
    }

    func testAppSettingsBackwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
          "theme": "dark",
          "glassIntensity": "medium",
          "hapticsEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertFalse(decoded.loreenVeilUnlocked)
        XCTAssertFalse(decoded.loreenVeilEnabled)
        XCTAssertTrue(decoded.loreenVeilApplyToTagdos)
        XCTAssertTrue(decoded.loreenVeilApplyToNotes)
        XCTAssertFalse(decoded.loreenVeilApplyToWidgets)
        XCTAssertFalse(decoded.loreenVeilRequireBiometricsForPeek)
        XCTAssertFalse(decoded.isLoreenVeilActiveForTagdos)
    }

    func testChallengeWordNormalization() {
        XCTAssertEqual(LoreenGlyphCatalog.normalizeChallengeWord("Ștefan"), "STEFAN")
        XCTAssertEqual(LoreenGlyphCatalog.normalizeChallengeWord("Mădălina-Îngrid"), "MADALINAINGRID")
        XCTAssertEqual(LoreenGlyphCatalog.challengeWord(for: "Mihai"), "MIHAI")
        XCTAssertEqual(LoreenGlyphCatalog.challengeWord(for: nil), "LOREEN")
        XCTAssertEqual(LoreenGlyphCatalog.challengeWord(for: "A"), "LOREEN")
    }

    func testCanonical26GlyphRecognitionAndNoiseTolerance() {
        XCTAssertEqual(LoreenGlyphCatalog.allGlyphs.count, 26)

        for def in LoreenGlyphCatalog.allGlyphs {
            // Scale canonical [0..1] strokes to typical 160x192 drawing tile pixels
            let pixelStrokes = def.strokes.map { stroke in
                stroke.map { LoreenPoint(x: $0.x * 160.0, y: $0.y * 192.0) }
            }
            XCTAssertTrue(
                LoreenStrokeRecognizer.matches(strokes: pixelStrokes, expected: def.id),
                "Canonical strokes should match \(def.id)"
            )

            // Reversed stroke order + reversed point direction should still match ($P invariance)
            let reversed = pixelStrokes.reversed().map { Array($0.reversed()) }
            XCTAssertTrue(
                LoreenStrokeRecognizer.matches(strokes: reversed, expected: def.id),
                "Reversed strokes should match \(def.id)"
            )

            // Slight deterministic jitter
            let noisy = pixelStrokes.enumerated().map { sIdx, stroke in
                stroke.enumerated().map { pIdx, pt in
                    let dx = sin(Double(sIdx * 7 + pIdx * 3)) * 2.5
                    let dy = cos(Double(sIdx * 5 + pIdx * 11)) * 2.5
                    return LoreenPoint(x: pt.x + dx, y: pt.y + dy)
                }
            }
            XCTAssertTrue(
                LoreenStrokeRecognizer.matches(strokes: noisy, expected: def.id),
                "Noisy strokes should match \(def.id)"
            )
        }
    }

    func testClearlyWrongGlyphsAreRejected() {
        let pairsToReject: [(Character, Character)] = [
            ("A", "L"),
            ("I", "O"),
            ("S", "Z"),
            ("K", "L"),
            ("P", "R"),
            ("U", "W"),
            ("F", "H")
        ]

        for (drawn, expected) in pairsToReject {
            guard let def = LoreenGlyphCatalog.definition(for: drawn) else {
                XCTFail("Missing \(drawn)")
                continue
            }
            let pixelStrokes = def.strokes.map { stroke in
                stroke.map { LoreenPoint(x: $0.x * 160.0, y: $0.y * 192.0) }
            }
            XCTAssertFalse(
                LoreenStrokeRecognizer.matches(strokes: pixelStrokes, expected: expected),
                "Drawing \(drawn) should NOT be accepted as \(expected)"
            )
        }
    }
}
