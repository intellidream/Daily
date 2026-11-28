package com.intellidream.daily.model

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

data class LoreenPoint(
    val x: Double,
    val y: Double
)

enum class LoreenGlyphOrigin {
    ORIGINAL,
    COMPLETED
}

data class LoreenGlyphDefinition(
    val id: Char,
    val origin: LoreenGlyphOrigin,
    val family: String,
    val summary: String,
    val strokes: List<List<LoreenPoint>>
)

object LoreenGlyphCatalog {
    fun normalizeChallengeWord(raw: String): String {
        val sb = StringBuilder()
        for (ch in raw.uppercase()) {
            when (ch) {
                'Ă', 'Â', 'Á', 'À', 'Ä', 'Å' -> sb.append('A')
                'Î', 'Í', 'Ì', 'Ï' -> sb.append('I')
                'Ș', 'Ş' -> sb.append('S')
                'Ț', 'Ţ' -> sb.append('T')
                'É', 'È', 'Ê', 'Ë' -> sb.append('E')
                'Ó', 'Ò', 'Ô', 'Ö' -> sb.append('O')
                'Ú', 'Ù', 'Û', 'Ü' -> sb.append('U')
                'Ñ' -> sb.append('N')
                'Ç' -> sb.append('C')
                in 'A'..'Z' -> sb.append(ch)
            }
        }
        return sb.toString()
    }

    fun challengeWord(firstName: String?): String {
        if (firstName.isNullOrBlank()) return "LOREEN"
        val normalized = normalizeChallengeWord(firstName)
        return if (normalized.length >= 2) normalized.take(10) else "LOREEN"
    }

    private fun pt(sx: Double, sy: Double): LoreenPoint = LoreenPoint(sx / 100.0, sy / 120.0)

    private fun circle(cx: Double, cy: Double, r: Double, steps: Int = 24): List<LoreenPoint> =
        ellipse(cx, cy, r, r, steps)

    private fun ellipse(cx: Double, cy: Double, rx: Double, ry: Double, steps: Int = 24): List<LoreenPoint> =
        (0..steps).map { k ->
            val a = (2.0 * PI * k) / steps
            pt(cx + rx * cos(a), cy + ry * sin(a))
        }

    private fun line(x1: Double, y1: Double, x2: Double, y2: Double, steps: Int = 8): List<LoreenPoint> =
        (0..steps).map { k ->
            val t = k.toDouble() / steps
            pt(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
        }

    private fun cubic(
        p0: Pair<Double, Double>,
        p1: Pair<Double, Double>,
        p2: Pair<Double, Double>,
        p3: Pair<Double, Double>,
        steps: Int = 14
    ): List<LoreenPoint> =
        (0..steps).map { k ->
            val t = k.toDouble() / steps
            val mt = 1.0 - t
            val x = mt * mt * mt * p0.first + 3 * mt * mt * t * p1.first + 3 * mt * t * t * p2.first + t * t * t * p3.first
            val y = mt * mt * mt * p0.second + 3 * mt * mt * t * p1.second + 3 * mt * t * t * p2.second + t * t * t * p3.second
            pt(x, y)
        }

    private fun arch(topSweep: Boolean): List<LoreenPoint> =
        if (topSweep) {
            val pts = line(20.0, 98.0, 20.0, 52.0, steps = 6).toMutableList()
            for (k in 1..15) {
                val a = PI + (PI * k) / 16.0
                pts.add(pt(50.0 + 30.0 * cos(a), 52.0 + 30.0 * sin(a)))
            }
            pts.addAll(line(80.0, 52.0, 80.0, 98.0, steps = 6))
            pts
        } else {
            val pts = line(22.0, 22.0, 22.0, 34.0, steps = 3).toMutableList()
            for (k in 1..15) {
                val a = PI - (PI * k) / 16.0
                pts.add(pt(50.0 + 28.0 * cos(a), 34.0 + 28.0 * sin(a)))
            }
            pts.addAll(line(78.0, 34.0, 78.0, 22.0, steps = 3))
            pts
        }

    val allGlyphs: List<LoreenGlyphDefinition> = listOf(
        LoreenGlyphDefinition(
            'A', LoreenGlyphOrigin.ORIGINAL, "Radial (Vowel)",
            "Empty circle — root of the radial vowel family",
            listOf(circle(50.0, 60.0, 38.0))
        ),
        LoreenGlyphDefinition(
            'B', LoreenGlyphOrigin.ORIGINAL, "Disguised Latin",
            "Fluid 2-curve loop",
            listOf(
                line(24.0, 24.0, 62.0, 24.0, steps = 5) +
                    cubic(62.0 to 24.0, 82.0 to 24.0, 84.0 to 52.0, 56.0 to 58.0, steps = 10) +
                    line(56.0, 58.0, 42.0, 62.0, steps = 3) +
                    cubic(42.0 to 62.0, 16.0 to 68.0, 18.0 to 96.0, 38.0 to 96.0, steps = 10) +
                    line(38.0, 96.0, 78.0, 96.0, steps = 5)
            )
        ),
        LoreenGlyphDefinition(
            'C', LoreenGlyphOrigin.ORIGINAL, "Bars & Rungs",
            "Open twin-pillar frame (0 rungs)",
            listOf(line(20.0, 22.0, 80.0, 22.0), line(20.0, 98.0, 80.0, 98.0), line(37.0, 22.0, 37.0, 98.0), line(63.0, 22.0, 63.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'D', LoreenGlyphOrigin.ORIGINAL, "Bars & Rungs",
            "Closed ladder frame with 3 rungs",
            listOf(
                line(24.0, 22.0, 76.0, 22.0) + line(76.0, 22.0, 76.0, 98.0) + line(76.0, 98.0, 24.0, 98.0) + line(24.0, 98.0, 24.0, 22.0),
                line(24.0, 41.0, 76.0, 41.0), line(24.0, 60.0, 76.0, 60.0), line(24.0, 79.0, 76.0, 79.0)
            )
        ),
        LoreenGlyphDefinition(
            'E', LoreenGlyphOrigin.ORIGINAL, "Radial (Vowel)",
            "Circle enclosing a 4-way cross",
            listOf(circle(50.0, 60.0, 38.0), line(12.0, 60.0, 88.0, 60.0), line(50.0, 22.0, 50.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'F', LoreenGlyphOrigin.ORIGINAL, "Recalled (PDF)",
            "Inverted triangle bisected by a full cross",
            listOf(
                line(18.0, 22.0, 82.0, 22.0) + line(82.0, 22.0, 50.0, 96.0) + line(50.0, 96.0, 18.0, 22.0),
                line(50.0, 22.0, 50.0, 98.0), line(24.0, 58.0, 76.0, 58.0)
            )
        ),
        LoreenGlyphDefinition(
            'G', LoreenGlyphOrigin.COMPLETED, "Radial",
            "Circle enclosing a diagonal X cross",
            listOf(circle(50.0, 60.0, 38.0), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9))
        ),
        LoreenGlyphDefinition(
            'H', LoreenGlyphOrigin.COMPLETED, "Radial",
            "Two full-height adjacent touching loops (infinity)",
            listOf(ellipse(26.5, 60.0, 23.5, 38.0, steps = 20), ellipse(73.5, 60.0, 23.5, 38.0, steps = 20))
        ),
        LoreenGlyphDefinition(
            'I', LoreenGlyphOrigin.ORIGINAL, "Radial / Cross",
            "Bare Latin cross",
            listOf(line(50.0, 22.0, 50.0, 98.0), line(28.0, 46.0, 72.0, 46.0))
        ),
        LoreenGlyphDefinition(
            'J', LoreenGlyphOrigin.ORIGINAL, "Architectural",
            "Vertical spine with top-left & bottom-right flags",
            listOf(
                line(20.0, 22.0, 50.0, 22.0) + line(50.0, 22.0, 50.0, 40.0) + line(50.0, 40.0, 20.0, 40.0) + line(20.0, 40.0, 20.0, 22.0),
                line(50.0, 40.0, 50.0, 80.0),
                line(50.0, 80.0, 80.0, 80.0) + line(80.0, 80.0, 80.0, 98.0) + line(80.0, 98.0, 50.0, 98.0) + line(50.0, 98.0, 50.0, 80.0)
            )
        ),
        LoreenGlyphDefinition(
            'K', LoreenGlyphOrigin.COMPLETED, "Architectural",
            "Inverted L — wide top block with descending stem",
            listOf(
                line(16.0, 22.0, 84.0, 22.0) + line(84.0, 22.0, 84.0, 48.0) + line(84.0, 48.0, 16.0, 48.0) + line(16.0, 48.0, 16.0, 22.0),
                line(40.0, 48.0, 40.0, 98.0) + line(40.0, 98.0, 60.0, 98.0) + line(60.0, 98.0, 60.0, 48.0)
            )
        ),
        LoreenGlyphDefinition(
            'L', LoreenGlyphOrigin.ORIGINAL, "Architectural",
            "Pedestal / top-hat — wide base block with rising stem",
            listOf(
                line(16.0, 72.0, 84.0, 72.0) + line(84.0, 72.0, 84.0, 98.0) + line(84.0, 98.0, 16.0, 98.0) + line(16.0, 98.0, 16.0, 72.0),
                line(40.0, 72.0, 40.0, 22.0) + line(40.0, 22.0, 60.0, 22.0) + line(60.0, 22.0, 60.0, 72.0)
            )
        ),
        LoreenGlyphDefinition(
            'M', LoreenGlyphOrigin.ORIGINAL, "Disguised Latin",
            "M with crossed inner legs",
            listOf(line(16.0, 98.0, 34.0, 22.0) + line(34.0, 22.0, 62.0, 98.0), line(38.0, 98.0, 66.0, 22.0) + line(66.0, 22.0, 84.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'N', LoreenGlyphOrigin.ORIGINAL, "Symmetric",
            "Opposing arches meeting at the center",
            listOf(
                cubic(20.0 to 22.0, 20.0 to 56.0, 36.0 to 60.0, 50.0 to 60.0, steps = 8) + cubic(50.0 to 60.0, 64.0 to 60.0, 80.0 to 56.0, 80.0 to 22.0, steps = 8),
                cubic(20.0 to 98.0, 20.0 to 64.0, 36.0 to 60.0, 50.0 to 60.0, steps = 8) + cubic(50.0 to 60.0, 64.0 to 60.0, 80.0 to 64.0, 80.0 to 98.0, steps = 8)
            )
        ),
        LoreenGlyphDefinition(
            'O', LoreenGlyphOrigin.ORIGINAL, "Radial (Vowel)",
            "Bare 8-ray star",
            listOf(line(50.0, 22.0, 50.0, 98.0), line(12.0, 60.0, 88.0, 60.0), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9))
        ),
        LoreenGlyphDefinition(
            'P', LoreenGlyphOrigin.COMPLETED, "Mirror Pair",
            "Horizontal mirror of R (triangle pointing left)",
            listOf(line(22.0, 22.0, 22.0, 98.0), line(78.0, 22.0, 78.0, 98.0), line(78.0, 22.0, 22.0, 60.0) + line(22.0, 60.0, 78.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'Q', LoreenGlyphOrigin.ORIGINAL, "Radial",
            "Circle enclosing an 8-ray star (A + O)",
            listOf(circle(50.0, 60.0, 38.0), line(50.0, 22.0, 50.0, 98.0), line(12.0, 60.0, 88.0, 60.0), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9))
        ),
        LoreenGlyphDefinition(
            'R', LoreenGlyphOrigin.ORIGINAL, "Mirror Pair",
            "Triangle pointing right between vertical rails",
            listOf(line(22.0, 22.0, 22.0, 98.0), line(78.0, 22.0, 78.0, 98.0), line(22.0, 22.0, 78.0, 60.0) + line(78.0, 60.0, 22.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'S', LoreenGlyphOrigin.COMPLETED, "Hourglass",
            "Empty vertical hourglass",
            listOf(line(20.0, 22.0, 80.0, 22.0) + line(80.0, 22.0, 20.0, 98.0) + line(20.0, 98.0, 80.0, 98.0) + line(80.0, 98.0, 20.0, 22.0))
        ),
        LoreenGlyphDefinition(
            'T', LoreenGlyphOrigin.COMPLETED, "Crosses",
            "Cross of Lorraine (paired with I)",
            listOf(line(50.0, 22.0, 50.0, 98.0), line(32.0, 42.0, 68.0, 42.0), line(22.0, 62.0, 78.0, 62.0))
        ),
        LoreenGlyphDefinition(
            'U', LoreenGlyphOrigin.ORIGINAL, "Arch & Bars",
            "Inverted open arch (0 crossbars)",
            listOf(arch(topSweep = true))
        ),
        LoreenGlyphDefinition(
            'V', LoreenGlyphOrigin.ORIGINAL, "Arch & Bars",
            "Inverted arch with 1 crossbar",
            listOf(arch(topSweep = true), line(20.0, 60.0, 80.0, 60.0))
        ),
        LoreenGlyphDefinition(
            'W', LoreenGlyphOrigin.ORIGINAL, "Arch & Bars",
            "Inverted arch with 2 crossbars",
            listOf(arch(topSweep = true), line(20.0, 52.0, 80.0, 52.0), line(20.0, 72.0, 80.0, 72.0))
        ),
        LoreenGlyphDefinition(
            'X', LoreenGlyphOrigin.ORIGINAL, "Symmetric",
            "Curved vertical vesica with 4 flared ends",
            listOf(
                cubic(20.0 to 22.0, 80.0 to 34.0, 80.0 to 86.0, 20.0 to 98.0, steps = 14),
                cubic(80.0 to 22.0, 20.0 to 34.0, 20.0 to 86.0, 80.0 to 98.0, steps = 14)
            )
        ),
        LoreenGlyphDefinition(
            'Y', LoreenGlyphOrigin.COMPLETED, "Arch & Bars",
            "Chalice / trident with tall inner vertical stem",
            listOf(arch(topSweep = false), line(50.0, 30.0, 50.0, 98.0))
        ),
        LoreenGlyphDefinition(
            'Z', LoreenGlyphOrigin.COMPLETED, "Hourglass",
            "90-degree rotation of S (empty horizontal bowtie)",
            listOf(line(16.0, 22.0, 16.0, 98.0) + line(16.0, 98.0, 84.0, 22.0) + line(84.0, 22.0, 84.0, 98.0) + line(84.0, 98.0, 16.0, 22.0))
        )
    )

    fun definition(letter: Char): LoreenGlyphDefinition? {
        val up = letter.uppercaseChar()
        return allGlyphs.firstOrNull { it.id == up }
    }
}
