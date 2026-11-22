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
}
