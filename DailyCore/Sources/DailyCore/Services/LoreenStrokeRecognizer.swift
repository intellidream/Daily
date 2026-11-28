import Foundation

public struct LoreenRecognitionCandidate: Equatable, Sendable {
    public let letter: Character
    public let distance: Double

    public init(letter: Character, distance: Double) {
        self.letter = letter
        self.distance = distance
    }
}

public struct LoreenRecognitionResult: Equatable, Sendable {
    public let letter: Character
    public let distance: Double
    public let topCandidates: [LoreenRecognitionCandidate]

    public init(letter: Character, distance: Double, topCandidates: [LoreenRecognitionCandidate]) {
        self.letter = letter
        self.distance = distance
        self.topCandidates = topCandidates
    }
}

/// Offline `$P` Point-Cloud Multistroke Recognizer (Vatavu et al., 2012) tuned for Loreen Script.
/// Stroke-order and stroke-direction invariant with geometric disambiguation guards for close pairs.
public enum LoreenStrokeRecognizer {
    private static let sampleCount = 32

    private struct NormalizedCloud {
        let points: [LoreenPoint]
        let centroidY: Double
        let aspectRatio: Double
        let horizontalStrokeCount: Int
        let verticalStrokeCount: Int
        let strokeCount: Int
        let leftMassFraction: Double
    }

    private struct Template {
        let letter: Character
        let cloud: NormalizedCloud
    }

    private static let templates: [Template] = LoreenGlyphCatalog.allGlyphs.map { def in
        Template(letter: def.id, cloud: normalize(strokes: def.strokes))
    }

    /// Recognizes a multi-stroke drawing into the closest Loreen letter.
    public static func recognize(strokes: [[LoreenPoint]]) -> LoreenRecognitionResult? {
        let validStrokes = strokes.filter { !$0.isEmpty }
        let totalRawPoints = validStrokes.reduce(0) { $0 + $1.count }
        guard !validStrokes.isEmpty, totalRawPoints >= 2 else { return nil }

        let candidate = normalize(strokes: validStrokes)
        var scored: [LoreenRecognitionCandidate] = []
        scored.reserveCapacity(templates.count)

        for template in templates {
            var d = greedyCloudMatch(candidate.points, template.cloud.points)
            d += disambiguationPenalty(candidate: candidate, target: template.letter)
            scored.append(LoreenRecognitionCandidate(letter: template.letter, distance: d))
        }

        scored.sort { $0.distance < $1.distance }
        guard let best = scored.first else { return nil }
        return LoreenRecognitionResult(
            letter: best.letter,
            distance: best.distance,
            topCandidates: Array(scored.prefix(4))
        )
    }

    /// Returns `true` when the user's strokes convincingly match the expected Loreen glyph.
    public static func matches(strokes: [[LoreenPoint]], expected: Character) -> Bool {
        let target = Character(String(expected).uppercased())
        guard let result = recognize(strokes: strokes) else { return false }

        // Reject tiny accidental taps
        let validStrokes = strokes.filter { !$0.isEmpty }
        let totalLen = validStrokes.reduce(0.0) { $0 + pathLength($1) }
        guard totalLen > 12.0 || totalLen > 0.18 else {
            // Note: works both in pixel coordinates (len > 12) and normalized [0,1] coordinates (len > 0.18)
            return false
        }

        if result.letter == target {
            return result.distance < 0.42
        }

        // Allow top-2 only when margin is very tight and not a structurally opposite pair
        if result.topCandidates.count >= 2,
           result.topCandidates[1].letter == target {
            let bestDist = max(0.001, result.topCandidates[0].distance)
            let targetDist = result.topCandidates[1].distance
            return targetDist < 0.36 && (targetDist / bestDist) <= 1.15
        }

        return false
    }

    // MARK: - Geometric Disambiguation Guards
    private static func disambiguationPenalty(candidate: NormalizedCloud, target: Character) -> Double {
        var penalty = 0.0

        switch target {
        case "I":
            if candidate.horizontalStrokeCount >= 2 { penalty += 0.14 }
        case "T":
            if candidate.horizontalStrokeCount <= 1 && candidate.strokeCount <= 2 { penalty += 0.14 }
        case "U":
            if candidate.horizontalStrokeCount >= 1 && candidate.strokeCount >= 2 { penalty += 0.14 }
        case "V":
            if candidate.strokeCount == 1 { penalty += 0.10 }
            if candidate.horizontalStrokeCount >= 2 { penalty += 0.10 }
        case "W":
            if candidate.horizontalStrokeCount < 2 && candidate.strokeCount < 3 { penalty += 0.12 }
        case "K":
            if candidate.centroidY > 0.56 { penalty += 0.14 }
        case "L":
            if candidate.centroidY < 0.44 { penalty += 0.14 }
        case "P":
            // P's triangle vertex points left -> more mass on right rails + left apex, vs R
            if candidate.leftMassFraction > 0.58 { penalty += 0.08 }
        case "R":
            if candidate.leftMassFraction < 0.42 { penalty += 0.08 }
        case "S":
            if candidate.verticalStrokeCount >= 2 && candidate.horizontalStrokeCount == 0 { penalty += 0.16 }
        case "Z":
            if candidate.horizontalStrokeCount >= 2 && candidate.verticalStrokeCount == 0 { penalty += 0.16 }
        case "H":
            if candidate.aspectRatio < 0.95 && candidate.strokeCount == 1 { penalty += 0.12 }
        case "A":
            if candidate.strokeCount >= 3 { penalty += 0.12 }
        case "Q":
            if candidate.strokeCount <= 2 { penalty += 0.14 }
        default:
            break
        }

        return penalty
    }

    // MARK: - $P Core Math
    private static func normalize(strokes: [[LoreenPoint]]) -> NormalizedCloud {
        var hCount = 0
        var vCount = 0

        // Compute raw bounding box first to analyze stroke orientations
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for stroke in strokes {
            for p in stroke {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        let rawW = max(1e-6, maxX - minX)
        let rawH = max(1e-6, maxY - minY)
        let aspect = rawW / rawH
        let scale = max(rawW, rawH)

        for stroke in strokes where stroke.count >= 2 {
            var sMinX = Double.infinity, sMaxX = -Double.infinity
            var sMinY = Double.infinity, sMaxY = -Double.infinity
            for p in stroke {
                sMinX = min(sMinX, p.x); sMaxX = max(sMaxX, p.x)
                sMinY = min(sMinY, p.y); sMaxY = max(sMaxY, p.y)
            }
            let sw = sMaxX - sMinX
            let sh = sMaxY - sMinY
            let len = pathLength(stroke)
            let isClosed = dist(stroke.first!, stroke.last!) < scale * 0.18 && len > scale * 0.8
            if !isClosed {
                if sw > sh * 2.2 && sw > scale * 0.25 {
                    hCount += 1
                } else if sh > sw * 2.2 && sh > scale * 0.25 {
                    vCount += 1
                }
            }
        }

        // Resample across all strokes proportionally to stroke lengths
        let resampled = resampleMultistroke(strokes, n: sampleCount)

        // Uniform aspect-preserving scale to [0, 1] + translate centroid to (0.5, 0.5)
        var rMinX = Double.infinity, rMaxX = -Double.infinity
        var rMinY = Double.infinity, rMaxY = -Double.infinity
        for p in resampled {
            rMinX = min(rMinX, p.x); rMaxX = max(rMaxX, p.x)
            rMinY = min(rMinY, p.y); rMaxY = max(rMaxY, p.y)
        }
        let rScale = max(1e-6, max(rMaxX - rMinX, rMaxY - rMinY))
        let scaled = resampled.map {
            LoreenPoint(x: ($0.x - rMinX) / rScale, y: ($0.y - rMinY) / rScale)
        }

        var sumX = 0.0, sumY = 0.0
        for p in scaled { sumX += p.x; sumY += p.y }
        let cx = sumX / Double(scaled.count)
        let cy = sumY / Double(scaled.count)

        let leftCount = scaled.filter { $0.x < 0.45 }.count
        let leftMass = Double(leftCount) / Double(scaled.count)

        let centered = scaled.map {
            LoreenPoint(x: $0.x - cx + 0.5, y: $0.y - cy + 0.5)
        }

        return NormalizedCloud(
            points: centered,
            centroidY: cy,
            aspectRatio: aspect,
            horizontalStrokeCount: hCount,
            verticalStrokeCount: vCount,
            strokeCount: strokes.count,
            leftMassFraction: leftMass
        )
    }

    private static func resampleMultistroke(_ strokes: [[LoreenPoint]], n: Int) -> [LoreenPoint] {
        let totalLen = strokes.reduce(0.0) { $0 + pathLength($1) }
        guard totalLen > 1e-6 else {
            let fallback = strokes.first?.first ?? LoreenPoint(x: 0.5, y: 0.5)
            return Array(repeating: fallback, count: n)
        }

        var result: [LoreenPoint] = []
        result.reserveCapacity(n)

        let lengths = strokes.map { pathLength($0) }
        var counts = lengths.map { max(1, Int(round(($0 / totalLen) * Double(n)))) }

        // Adjust counts so sum == n
        var diff = counts.reduce(0, +) - n
        while diff != 0 {
            if diff > 0 {
                if let idx = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[idx] > 1 {
                    counts[idx] -= 1
                    diff -= 1
                } else { break }
            } else {
                if let idx = counts.indices.max(by: { lengths[$0] < lengths[$1] }) {
                    counts[idx] += 1
                    diff += 1
                } else { break }
            }
        }

        for (stroke, count) in zip(strokes, counts) {
            result.append(contentsOf: resampleSingle(stroke, n: count))
        }
        return result
    }

    private static func resampleSingle(_ raw: [LoreenPoint], n: Int) -> [LoreenPoint] {
        if raw.isEmpty { return [] }
        if raw.count == 1 || n == 1 { return Array(repeating: raw[0], count: n) }

        var pts = raw
        let len = pathLength(pts)
        if len < 1e-6 { return Array(repeating: pts[0], count: n) }

        let interval = len / Double(n - 1)
        var D = 0.0
        var newPts: [LoreenPoint] = [pts[0]]
        var i = 1
        while i < pts.count {
            let d = dist(pts[i - 1], pts[i])
            if D + d >= interval && d > 1e-9 {
                let qx = pts[i - 1].x + ((interval - D) / d) * (pts[i].x - pts[i - 1].x)
                let qy = pts[i - 1].y + ((interval - D) / d) * (pts[i].y - pts[i - 1].y)
                let q = LoreenPoint(x: qx, y: qy)
                newPts.append(q)
                pts.insert(q, at: i)
                D = 0.0
            } else {
                D += d
            }
            i += 1
        }
        while newPts.count < n {
            newPts.append(pts.last!)
        }
        if newPts.count > n {
            newPts = Array(newPts.prefix(n))
        }
        return newPts
    }

    private static func greedyCloudMatch(_ a: [LoreenPoint], _ b: [LoreenPoint]) -> Double {
        let eps = 0.5
        let step = max(1, Int(floor(pow(Double(a.count), 1.0 - eps))))
        var minDist = Double.infinity
        var i = 0
        while i < a.count {
            let d1 = cloudDistance(a, b, start: i)
            let d2 = cloudDistance(b, a, start: i)
            minDist = min(minDist, min(d1, d2))
            i += step
        }
        return minDist
    }

    private static func cloudDistance(_ a: [LoreenPoint], _ b: [LoreenPoint], start: Int) -> Double {
        let n = a.count
        var matched = Array(repeating: false, count: n)
        var sum = 0.0
        var i = start
        var visited = 0
        repeat {
            var best = Double.infinity
            var bestIdx = -1
            for j in 0..<n where !matched[j] {
                let d = dist(a[i], b[j])
                if d < best {
                    best = d
                    bestIdx = j
                }
            }
            if bestIdx >= 0 {
                matched[bestIdx] = true
                let weight = 1.0 - Double(visited) / Double(n)
                sum += weight * best
            }
            i = (i + 1) % n
            visited += 1
        } while i != start
        return sum / Double(n)
    }

    private static func pathLength(_ pts: [LoreenPoint]) -> Double {
        guard pts.count >= 2 else { return 0.0 }
        var sum = 0.0
        for i in 1..<pts.count {
            sum += dist(pts[i - 1], pts[i])
        }
        return sum
    }

    private static func dist(_ a: LoreenPoint, _ b: LoreenPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
