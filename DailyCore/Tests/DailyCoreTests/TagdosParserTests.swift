import XCTest
@testable import DailyCore

final class TagdosParserTests: XCTestCase {

    func testUpdatePillTextReclassifiesSemanticTypeAndPreservesPosition() {
        let parser = TagdosParser.shared
        let stream = parser.parseStream(rawText: "MG/GM/TG & FSH/LDL", title: "Daily Ops")
        let targetPill = stream.clusters[0].pills[1] // "GM"

        let updated = parser.updatePillText(in: stream, pillId: targetPill.id, newText: "C$T!")
        XCTAssertEqual(updated.clusters[0].pills[1].id, targetPill.id)
        XCTAssertEqual(updated.clusters[0].pills[1].rawText, "C$T!")
        XCTAssertEqual(updated.clusters[0].pills[1].type, .financial)
        XCTAssertEqual(updated.rawText, "MG/C$T!/TG & FSH/LDL")

        let metricUpdated = parser.updatePillText(in: updated, pillId: targetPill.id, newText: "14:00")
        XCTAssertEqual(metricUpdated.clusters[0].pills[1].type, .temporalOrMetric)
        XCTAssertEqual(metricUpdated.rawText, "MG/14:00/TG & FSH/LDL")
    }

    func testDslDetectionRecognizesTagdosSyntaxVsNaturalLanguage() {
        let parser = TagdosParser.shared

        XCTAssertTrue(parser.isAlreadyTagdosDsl("MG/GM/TG & FSH/LDL"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("C$T"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("EXP!"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("5K"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("€100"))

        XCTAssertFalse(parser.isAlreadyTagdosDsl("Pay electricity bill"))
        XCTAssertFalse(parser.isAlreadyTagdosDsl("Schedule dentist appointment"))
        XCTAssertFalse(parser.isAlreadyTagdosDsl("Groceries"))
    }

    func testPrepareImportItemHandlesDslAndNaturalLanguageDifferently() {
        let parser = TagdosParser.shared

        let dslPrep = parser.prepareImportItem(title: "FIT/GYM & RUN/5K", notes: nil, isHighImportance: false)
        XCTAssertTrue(dslPrep.isAlreadyDsl)
        XCTAssertEqual(dslPrep.tagOrDsl, "FIT/GYM & RUN/5K")
        XCTAssertNil(dslPrep.memoEntry)

        let prosePrep = parser.prepareImportItem(
            title: "Pay electricity bill",
            notes: "Due on Friday",
            isHighImportance: true
        )
        XCTAssertFalse(prosePrep.isAlreadyDsl)
        XCTAssertTrue(prosePrep.tagOrDsl.contains("$"))
        XCTAssertTrue(prosePrep.tagOrDsl.contains("!"))
        XCTAssertEqual(prosePrep.memoEntry, "• [\(prosePrep.tagOrDsl)] Pay electricity bill — Due on Friday")
    }

    func testAesGcmTokenDecryptPeelsSingleAndDoubleEncryption() {
        let userId = "a1b2c3d4-e5f6-4711-8222-333344445555"
        let plainToken = "ya29.sample_google_oauth_token_123"

        let layer1 = TagdosExternalTasksService.encryptToken(plainToken, keyScope: userId)
        XCTAssertEqual(TagdosExternalTasksService.decryptToken(layer1, keyScope: userId), plainToken)

        let layer2 = TagdosExternalTasksService.encryptToken(layer1, keyScope: userId)
        XCTAssertEqual(TagdosExternalTasksService.decryptToken(layer2, keyScope: userId), plainToken)
    }
}
