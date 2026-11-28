package com.intellidream.daily.model

import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

data class LoreenRecognitionCandidate(
    val letter: Char,
    val distance: Double
)

data class LoreenRecognitionResult(
    val letter: Char,
    val distance: Double,
    val topCandidates: List<LoreenRecognitionCandidate>
)

/**
 * Offline `$P` Point-Cloud Multistroke Recognizer (Vatavu et al., 2012) tuned for Loreen Script.
 * Stroke-order and stroke-direction invariant with geometric disambiguation guards for close pairs.
 */
object LoreenStrokeRecognizer {
    private const val SAMPLE_COUNT = 32

    private data class NormalizedCloud(
        val points: List<LoreenPoint>,
        val centroidY: Double,
        val aspectRatio: Double,
        val horizontalStrokeCount: Int,
        val verticalStrokeCount: Int,
        val strokeCount: Int,
        val leftMassFraction: Double
    )

    private data class Template(
        val letter: Char,
        val cloud: NormalizedCloud
    )

    private val templates: List<Template> by lazy {
        LoreenGlyphCatalog.allGlyphs.map { def ->
            Template(letter = def.id, cloud = normalize(def.strokes))
        }
    }

    fun recognize(strokes: List<List<LoreenPoint>>): LoreenRecognitionResult? {
        val validStrokes = strokes.filter { it.isNotEmpty() }
        val totalRawPoints = validStrokes.sumOf { it.size }
        if (validStrokes.isEmpty() || totalRawPoints < 2) return null

        val candidate = normalize(validStrokes)
        val scored = templates.map { template ->
            val d = greedyCloudMatch(candidate.points, template.cloud.points) +
                disambiguationPenalty(candidate, template.letter)
            LoreenRecognitionCandidate(letter = template.letter, distance = d)
        }.sortedBy { it.distance }

        val best = scored.firstOrNull() ?: return null
        return LoreenRecognitionResult(
            letter = best.letter,
            distance = best.distance,
            topCandidates = scored.take(4)
        )
    }

    fun matches(strokes: List<List<LoreenPoint>>, expected: Char): Boolean {
        val target = expected.uppercaseChar()
        val result = recognize(strokes) ?: return false

        val validStrokes = strokes.filter { it.isNotEmpty() }
        val totalLen = validStrokes.sumOf { pathLength(it) }
        if (totalLen <= 0.18) return false

        if (result.letter == target) {
            return result.distance < 0.42
        }

        if (result.topCandidates.size >= 2 && result.topCandidates[1].letter == target) {
            val bestDist = max(0.001, result.topCandidates[0].distance)
            val targetDist = result.topCandidates[1].distance
            return targetDist < 0.36 && (targetDist / bestDist) <= 1.15
        }

        return false
    }

    private fun disambiguationPenalty(candidate: NormalizedCloud, target: Char): Double {
        var penalty = 0.0
        when (target) {
            'I' -> if (candidate.horizontalStrokeCount >= 2) penalty += 0.14
            'T' -> if (candidate.horizontalStrokeCount <= 1 && candidate.strokeCount <= 2) penalty += 0.14
            'U' -> if (candidate.horizontalStrokeCount >= 1 && candidate.strokeCount >= 2) penalty += 0.14
            'V' -> {
                if (candidate.strokeCount == 1) penalty += 0.10
                if (candidate.horizontalStrokeCount >= 2) penalty += 0.10
            }
            'W' -> if (candidate.horizontalStrokeCount < 2 && candidate.strokeCount < 3) penalty += 0.12
            'K' -> if (candidate.centroidY > 0.56) penalty += 0.14
            'L' -> if (candidate.centroidY < 0.44) penalty += 0.14
            'P' -> if (candidate.leftMassFraction > 0.58) penalty += 0.08
            'R' -> if (candidate.leftMassFraction < 0.42) penalty += 0.08
            'S' -> if (candidate.verticalStrokeCount >= 2 && candidate.horizontalStrokeCount == 0) penalty += 0.16
            'Z' -> if (candidate.horizontalStrokeCount >= 2 && candidate.verticalStrokeCount == 0) penalty += 0.16
            'H' -> if (candidate.aspectRatio < 0.95 && candidate.strokeCount == 1) penalty += 0.12
            'A' -> if (candidate.strokeCount >= 3) penalty += 0.12
            'Q' -> if (candidate.strokeCount <= 2) penalty += 0.14
        }
        return penalty
    }

    private fun normalize(strokes: List<List<LoreenPoint>>): NormalizedCloud {
        var hCount = 0
        var vCount = 0

        var minX = Double.POSITIVE_INFINITY
        var maxX = Double.NEGATIVE_INFINITY
        var minY = Double.POSITIVE_INFINITY
        var maxY = Double.NEGATIVE_INFINITY
        for (stroke in strokes) {
            for (p in stroke) {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        val rawW = max(1e-6, maxX - minX)
        val rawH = max(1e-6, maxY - minY)
        val aspect = rawW / rawH
        val scale = max(rawW, rawH)

        for (stroke in strokes) {
            if (stroke.size < 2) continue
            var sMinX = Double.POSITIVE_INFINITY
            var sMaxX = Double.NEGATIVE_INFINITY
            var sMinY = Double.POSITIVE_INFINITY
            var sMaxY = Double.NEGATIVE_INFINITY
            for (p in stroke) {
                sMinX = min(sMinX, p.x); sMaxX = max(sMaxX, p.x)
                sMinY = min(sMinY, p.y); sMaxY = max(sMaxY, p.y)
            }
            val sw = sMaxX - sMinX
            val sh = sMaxY - sMinY
            val len = pathLength(stroke)
            val isClosed = dist(stroke.first(), stroke.last()) < scale * 0.18 && len > scale * 0.8
            if (!isClosed) {
                if (sw > sh * 2.2 && sw > scale * 0.25) {
                    hCount += 1
                } else if (sh > sw * 2.2 && sh > scale * 0.25) {
                    vCount += 1
                }
            }
        }

        val resampled = resampleMultistroke(strokes, SAMPLE_COUNT)
        var rMinX = Double.POSITIVE_INFINITY
        var rMaxX = Double.NEGATIVE_INFINITY
        var rMinY = Double.POSITIVE_INFINITY
        var rMaxY = Double.NEGATIVE_INFINITY
        for (p in resampled) {
            rMinX = min(rMinX, p.x); rMaxX = max(rMaxX, p.x)
            rMinY = min(rMinY, p.y); rMaxY = max(rMaxY, p.y)
        }
        val rScale = max(1e-6, max(rMaxX - rMinX, rMaxY - rMinY))
        val scaled = resampled.map { LoreenPoint((it.x - rMinX) / rScale, (it.y - rMinY) / rScale) }

        val cx = scaled.sumOf { it.x } / scaled.size
        val cy = scaled.sumOf { it.y } / scaled.size
        val leftMass = scaled.count { it.x < 0.45 }.toDouble() / scaled.size
        val centered = scaled.map { LoreenPoint(it.x - cx + 0.5, it.y - cy + 0.5) }

        return NormalizedCloud(
            points = centered,
            centroidY = cy,
            aspectRatio = aspect,
            horizontalStrokeCount = hCount,
            verticalStrokeCount = vCount,
            strokeCount = strokes.size,
            leftMassFraction = leftMass
        )
    }

    private fun resampleMultistroke(strokes: List<List<LoreenPoint>>, n: Int): List<LoreenPoint> {
        val totalLen = strokes.sumOf { pathLength(it) }
        if (totalLen <= 1e-6) {
            val fallback = strokes.firstOrNull()?.firstOrNull() ?: LoreenPoint(0.5, 0.5)
            return List(n) { fallback }
        }

        val lengths = strokes.map { pathLength(it) }
        val counts = lengths.map { max(1, ((it / totalLen) * n).roundToInt()) }.toMutableList()

        var diff = counts.sum() - n
        while (diff != 0) {
            if (diff > 0) {
                val idx = counts.indices.maxByOrNull { counts[it] } ?: break
                if (counts[idx] > 1) {
                    counts[idx] -= 1
                    diff -= 1
                } else break
            } else {
                val idx = counts.indices.maxByOrNull { lengths[it] } ?: break
                counts[idx] += 1
                diff += 1
            }
        }

        val result = ArrayList<LoreenPoint>(n)
        for (i in strokes.indices) {
            result.addAll(resampleSingle(strokes[i], counts[i]))
        }
        return result
    }

    private fun resampleSingle(raw: List<LoreenPoint>, n: Int): List<LoreenPoint> {
        if (raw.isEmpty()) return emptyList()
        if (raw.size == 1 || n == 1) return List(n) { raw[0] }

        val pts = raw.toMutableList()
        val len = pathLength(pts)
        if (len <= 1e-6) return List(n) { pts[0] }

        val interval = len / (n - 1)
        var acc = 0.0
        val newPts = ArrayList<LoreenPoint>(n)
        newPts.add(pts[0])
        var i = 1
        while (i < pts.size) {
            val d = dist(pts[i - 1], pts[i])
            if (acc + d >= interval && d > 1e-9) {
                val qx = pts[i - 1].x + ((interval - acc) / d) * (pts[i].x - pts[i - 1].x)
                val qy = pts[i - 1].y + ((interval - acc) / d) * (pts[i].y - pts[i - 1].y)
                val q = LoreenPoint(qx, qy)
                newPts.add(q)
                pts.add(i, q)
                acc = 0.0
            } else {
                acc += d
            }
            i++
        }
        while (newPts.size < n) {
            newPts.add(pts.last())
        }
        return if (newPts.size > n) newPts.take(n) else newPts
    }

    private fun greedyCloudMatch(a: List<LoreenPoint>, b: List<LoreenPoint>): Double {
        val eps = 0.5
        val step = max(1, floor(a.size.toDouble().pow(1.0 - eps)).toInt())
        var minDist = Double.POSITIVE_INFINITY
        var i = 0
        while (i < a.size) {
            val d1 = cloudDistance(a, b, i)
            val d2 = cloudDistance(b, a, i)
            minDist = min(minDist, min(d1, d2))
            i += step
        }
        return minDist
    }

    private fun cloudDistance(a: List<LoreenPoint>, b: List<LoreenPoint>, start: Int): Double {
        val n = a.size
        val matched = BooleanArray(n)
        var sum = 0.0
        var i = start
        var visited = 0
        do {
            var best = Double.POSITIVE_INFINITY
            var bestIdx = -1
            for (j in 0 until n) {
                if (!matched[j]) {
                    val d = dist(a[i], b[j])
                    if (d < best) {
                        best = d
                        bestIdx = j
                    }
                }
            }
            if (bestIdx >= 0) {
                matched[bestIdx] = true
                val weight = 1.0 - visited.toDouble() / n
                sum += weight * best
            }
            i = (i + 1) % n
            visited += 1
        } while (i != start)
        return sum / n
    }

    private fun pathLength(pts: List<LoreenPoint>): Double {
        if (pts.size < 2) return 0.0
        var sum = 0.0
        for (i in 1 until pts.size) {
            sum += dist(pts[i - 1], pts[i])
        }
        return sum
    }

    private fun dist(a: LoreenPoint, b: LoreenPoint): Double = hypot(a.x - b.x, a.y - b.y)
}
