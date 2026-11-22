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
        XCTAssertTrue(parser.isAlreadyTagdosDsl("CRR vg/PL 98 & DOC sign"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("C$T"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("EXP!"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("5K"))
        XCTAssertTrue(parser.isAlreadyTagdosDsl("€100"))

        XCTAssertFalse(parser.isAlreadyTagdosDsl("Pay electricity bill"))
        XCTAssertFalse(parser.isAlreadyTagdosDsl("Schedule dentist appointment"))
        XCTAssertFalse(parser.isAlreadyTagdosDsl("Groceries"))
        XCTAssertFalse(parser.isAlreadyTagdosDsl("Meet John on 12/05 about budget proposal"))
    }

    func testPrepareImportItemHandlesDslAndNaturalLanguageDifferently() {
        let parser = TagdosParser.shared

        let dslPrep = parser.prepareImportItem(title: "FIT/GYM & RUN/5K", notes: nil, isHighImportance: false)
        XCTAssertTrue(dslPrep.isAlreadyDsl)
        XCTAssertEqual(dslPrep.tagOrDsl, "FIT/GYM & RUN/5K")
        XCTAssertNil(dslPrep.memoEntry)

        let dslWithNotes = parser.prepareImportItem(title: "CRR vg/PL 98", notes: "Plain memo body", isHighImportance: false)
        XCTAssertTrue(dslWithNotes.isAlreadyDsl)
        XCTAssertEqual(dslWithNotes.tagOrDsl, "CRR vg/PL 98")
        XCTAssertEqual(dslWithNotes.memoEntry, "Plain memo body")

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

    @MainActor
    func testReminderSpecEncodingClusterPreservationAndWidgetSnapshot() {
        let parser = TagdosParser.shared
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let tStream = fmt.date(from: "17:30")!
        let tCluster0 = fmt.date(from: "08:45")!
        let tCluster1 = fmt.date(from: "14:15")!

        var stream = parser.parseStream(rawText: "MG/GM/TG & FSH/LDL", title: "Daily Ops", streamReminder: tStream)
        XCTAssertEqual(TagdosStore.encodeReminderSpec(for: stream), "17:30")

        stream.clusters[0].reminderDate = tCluster0
        stream.clusters[1].reminderDate = tCluster1
        let spec = TagdosStore.encodeReminderSpec(for: stream)
        XCTAssertEqual(spec, "17:30|0=08:45,1=14:15")

        let decoded = TagdosStore.decodeReminderSpec(spec)
        XCTAssertEqual(decoded.streamReminder.map { fmt.string(from: $0) }, "17:30")
        XCTAssertEqual(decoded.clusterReminders[0].map { fmt.string(from: $0) }, "08:45")
        XCTAssertEqual(decoded.clusterReminders[1].map { fmt.string(from: $0) }, "14:15")

        // Cluster-only reminder (no stream reminder)
        stream.streamReminder = nil
        let clusterOnlySpec = TagdosStore.encodeReminderSpec(for: stream)
        XCTAssertEqual(clusterOnlySpec, "|0=08:45,1=14:15")
        let decodedClusterOnly = TagdosStore.decodeReminderSpec(clusterOnlySpec)
        XCTAssertNil(decodedClusterOnly.streamReminder)
        XCTAssertEqual(decodedClusterOnly.clusterReminders[0].map { fmt.string(from: $0) }, "08:45")

        // Preserving cluster reminder across parseStream
        let reparsed = parser.parseStream(
            rawText: "MG/GM/TG/NEW & FSH/LDL",
            title: "Daily Ops",
            id: stream.id,
            existingStream: stream
        )
        XCTAssertEqual(reparsed.clusters[0].reminderDate, tCluster0)
        XCTAssertEqual(reparsed.clusters[1].reminderDate, tCluster1)

        // Widget snapshot includes drivingPillId, pill IDs, and earliest cluster/stream reminder
        let snap = TagdosStore.buildWidgetSnapshot(from: [reparsed])
        XCTAssertEqual(snap.streams.first?.drivingPillId, reparsed.drivingPill?.id.uuidString)
        XCTAssertEqual(snap.streams.first?.pills.first?.id, reparsed.activePills.first?.id.uuidString)
        XCTAssertEqual(snap.nextReminderFormatted, "08:45")
    }

    func testMakeSupabaseDecoderSupportsFractionalAndWholeIsoTimestamps() throws {
        struct StampWrapper: Decodable { let updated_at: Date }
        let decoder = TagdosStore.makeSupabaseDecoder()

        let fracData = #"{"updated_at":"2026-11-22T19:02:21.662265Z"}"#.data(using: .utf8)!
        let fracDecoded = try decoder.decode(StampWrapper.self, from: fracData)
        XCTAssertGreaterThan(fracDecoded.updated_at.timeIntervalSince1970, 1_700_000_000)

        let stdData = #"{"updated_at":"2026-11-22T19:02:21Z"}"#.data(using: .utf8)!
        let stdDecoded = try decoder.decode(StampWrapper.self, from: stdData)
        XCTAssertGreaterThan(stdDecoded.updated_at.timeIntervalSince1970, 1_700_000_000)
    }
}
