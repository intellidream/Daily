package com.intellidream.daily.model

import org.junit.Assert.*
import org.junit.Test

class TagdosParserTest {

    @Test
    fun updatePillTextReclassifiesSemanticTypeAndPreservesPosition() {
        val stream = TagdosParser.parseStream(rawText = "MG/GM/TG & FSH/LDL", title = "Daily Ops")
        val targetPill = stream.clusters[0].pills[1]

        val updated = TagdosParser.updatePillText(stream, targetPill.id, "C\$T!")
        assertEquals(targetPill.id, updated.clusters[0].pills[1].id)
        assertEquals("C\$T!", updated.clusters[0].pills[1].rawText)
        assertEquals(TagDoPillType.Financial, updated.clusters[0].pills[1].type)
        assertEquals("MG/C\$T!/TG & FSH/LDL", updated.rawText)

        val metricUpdated = TagdosParser.updatePillText(updated, targetPill.id, "14:00")
        assertEquals(TagDoPillType.TemporalOrMetric, metricUpdated.clusters[0].pills[1].type)
        assertEquals("MG/14:00/TG & FSH/LDL", metricUpdated.rawText)
    }

    @Test
    fun dslDetectionRecognizesTagdosSyntaxVsNaturalLanguage() {
        assertTrue(TagdosParser.isAlreadyTagdosDsl("MG/GM/TG & FSH/LDL"))
        assertTrue(TagdosParser.isAlreadyTagdosDsl("CRR vg/PL 98 & DOC sign"))
        assertTrue(TagdosParser.isAlreadyTagdosDsl("C\$T"))
        assertTrue(TagdosParser.isAlreadyTagdosDsl("EXP!"))
        assertTrue(TagdosParser.isAlreadyTagdosDsl("5K"))
        assertTrue(TagdosParser.isAlreadyTagdosDsl("€100"))

        assertFalse(TagdosParser.isAlreadyTagdosDsl("Pay electricity bill"))
        assertFalse(TagdosParser.isAlreadyTagdosDsl("Schedule dentist appointment"))
        assertFalse(TagdosParser.isAlreadyTagdosDsl("Groceries"))
        assertFalse(TagdosParser.isAlreadyTagdosDsl("Meet John on 12/05 about budget proposal"))
    }

    @Test
    fun prepareImportItemHandlesDslAndNaturalLanguageDifferently() {
        val (dslTag, isDsl, dslMemo) = TagdosParser.prepareImportItem("FIT/GYM & RUN/5K", null, false)
        assertTrue(isDsl)
        assertEquals("FIT/GYM & RUN/5K", dslTag)
        assertNull(dslMemo)

        val (dslNotesTag, isNotesDsl, plainMemo) = TagdosParser.prepareImportItem("CRR vg/PL 98", "Plain memo body", false)
        assertTrue(isNotesDsl)
        assertEquals("CRR vg/PL 98", dslNotesTag)
        assertEquals("Plain memo body", plainMemo)

        val (proseTag, isProseDsl, proseMemo) = TagdosParser.prepareImportItem(
            title = "Pay electricity bill",
            notes = "Due on Friday",
            isHighImportance = true
        )
        assertFalse(isProseDsl)
        assertTrue(proseTag.contains("$"))
        assertTrue(proseTag.contains("!"))
        assertEquals("• [$proseTag] Pay electricity bill — Due on Friday", proseMemo)
    }

    @Test
    fun reminderSpecEncodingAndClusterPreservationRoundTrip() {
        val fmt = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
        fun ts(hhmm: String): Long {
            val p = hhmm.split(":")
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.HOUR_OF_DAY, p[0].toInt())
            cal.set(java.util.Calendar.MINUTE, p[1].toInt())
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }

        val base = TagdosParser.parseStream(rawText = "MG/GM/TG & FSH/LDL", title = "Daily Ops", streamReminder = ts("17:30"))
        assertEquals("17:30", TagdosParser.encodeReminderSpec(base))

        val withClusters = base.copy(
            clusters = listOf(
                base.clusters[0].copy(reminderTime = ts("08:45")),
                base.clusters[1].copy(reminderTime = ts("14:15"))
            )
        )
        val encoded = TagdosParser.encodeReminderSpec(withClusters)
        assertEquals("17:30|0=08:45,1=14:15", encoded)

        val (decodedStream, decodedClusters) = TagdosParser.decodeReminderSpec(encoded)
        assertEquals("17:30", decodedStream?.let { fmt.format(java.util.Date(it)) })
        assertEquals("08:45", decodedClusters[0]?.let { fmt.format(java.util.Date(it)) })
        assertEquals("14:15", decodedClusters[1]?.let { fmt.format(java.util.Date(it)) })

        val reparsed = TagdosParser.parseStream(
            rawText = "MG/GM/TG/NEW & FSH/LDL",
            title = "Daily Ops",
            id = withClusters.id,
            streamReminder = withClusters.streamReminder,
            existingStream = withClusters
        )
        assertEquals(withClusters.clusters[0].reminderTime, reparsed.clusters[0].reminderTime)
        assertEquals(withClusters.clusters[1].reminderTime, reparsed.clusters[1].reminderTime)
    }
}
