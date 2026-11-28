package com.intellidream.daily.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class LoreenRecognizerTest {

    @Test
    fun appSettingsBackwardCompatibleDecoding() {
        val json = Json { ignoreUnknownKeys = true }
        val legacyJson = """{"theme":"Dark","hapticsEnabled":true}"""
        val decoded = json.decodeFromString<AppSettings>(legacyJson)
        assertFalse(decoded.loreenVeilUnlocked)
        assertFalse(decoded.loreenVeilEnabled)
        assertTrue(decoded.loreenVeilApplyToTagdos)
        assertTrue(decoded.loreenVeilApplyToNotes)
        assertFalse(decoded.loreenVeilApplyToWidgets)
        assertFalse(decoded.loreenVeilRequireBiometricsForPeek)
        assertFalse(decoded.isLoreenVeilActiveForTagdos)
    }

    @Test
    fun challengeWordNormalization() {
        assertEquals("STEFAN", LoreenGlyphCatalog.normalizeChallengeWord("Ștefan"))
        assertEquals("MADALINAINGRID", LoreenGlyphCatalog.normalizeChallengeWord("Mădălina-Îngrid"))
        assertEquals("MIHAI", LoreenGlyphCatalog.challengeWord("Mihai"))
        assertEquals("LOREEN", LoreenGlyphCatalog.challengeWord(null))
        assertEquals("LOREEN", LoreenGlyphCatalog.challengeWord("A"))
    }

    @Test
    fun canonical26GlyphRecognitionAndNoiseTolerance() {
        assertEquals(26, LoreenGlyphCatalog.allGlyphs.size)
        for (def in LoreenGlyphCatalog.allGlyphs) {
            val pixelStrokes = def.strokes.map { stroke ->
                stroke.map { LoreenPoint(it.x * 160.0, it.y * 192.0) }
            }
            assertTrue("Canonical strokes should match ${def.id}", LoreenStrokeRecognizer.matches(pixelStrokes, def.id))

            val reversed = pixelStrokes.reversed().map { it.reversed() }
            assertTrue("Reversed strokes should match ${def.id}", LoreenStrokeRecognizer.matches(reversed, def.id))

            val noisy = pixelStrokes.mapIndexed { sIdx, stroke ->
                stroke.mapIndexed { pIdx, pt ->
                    val dx = sin((sIdx * 7 + pIdx * 3).toDouble()) * 2.5
                    val dy = cos((sIdx * 5 + pIdx * 11).toDouble()) * 2.5
                    LoreenPoint(pt.x + dx, pt.y + dy)
                }
            }
            assertTrue("Noisy strokes should match ${def.id}", LoreenStrokeRecognizer.matches(noisy, def.id))
        }
    }

    @Test
    fun clearlyWrongGlyphsAreRejected() {
        val pairs = listOf(
            'A' to 'L',
            'I' to 'O',
            'S' to 'Z',
            'K' to 'L',
            'P' to 'R',
            'U' to 'W',
            'F' to 'H'
        )
        for ((drawn, expected) in pairs) {
            val def = LoreenGlyphCatalog.definition(drawn)!!
            val pixelStrokes = def.strokes.map { stroke ->
                stroke.map { LoreenPoint(it.x * 160.0, it.y * 192.0) }
            }
            assertFalse("Drawing $drawn should NOT match $expected", LoreenStrokeRecognizer.matches(pixelStrokes, expected))
        }
    }
}
