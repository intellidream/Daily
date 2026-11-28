import Foundation

/// A single 2D coordinate sampled in a stroke (normalized or canvas-local).
public struct LoreenPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum LoreenGlyphOrigin: String, Codable, Sendable {
    case original
    case completed
}

/// Canonical definition of one Loreen Script letter (A-Z), including origin metadata and reference strokes.
public struct LoreenGlyphDefinition: Identifiable, Sendable {
    public let id: Character
    public let origin: LoreenGlyphOrigin
    public let family: String
    public let summary: String
    public let strokes: [[LoreenPoint]]

    public init(
        id: Character,
        origin: LoreenGlyphOrigin,
        family: String,
        summary: String,
        strokes: [[LoreenPoint]]
    ) {
        self.id = id
        self.origin = origin
        self.family = family
        self.summary = summary
        self.strokes = strokes
    }
}

/// Shared catalog of all 26 Loreen Script glyphs + challenge-word normalization helpers.
public enum LoreenGlyphCatalog {
    /// Normalizes Romanian diacritics and strips non-Latin A-Z characters for challenge words.
    public static func normalizeChallengeWord(_ raw: String) -> String {
        var out = ""
        for ch in raw.uppercased() {
            switch ch {
            case "Ă", "Â", "Á", "À", "Ä", "Å": out.append("A")
            case "Î", "Í", "Ì", "Ï": out.append("I")
            case "Ș", "Ş": out.append("S")
            case "Ț", "Ţ": out.append("T")
            case "É", "È", "Ê", "Ë": out.append("E")
            case "Ó", "Ò", "Ô", "Ö": out.append("O")
            case "Ú", "Ù", "Û", "Ü": out.append("U")
            case "Ñ": out.append("N")
            case "Ç": out.append("C")
            case "A"..."Z": out.append(ch)
            default: break
            }
        }
        return out
    }

    /// Resolves a challenge word from the user's first name (falling back to `"LOREEN"` if invalid/too short).
    public static func challengeWord(for firstName: String?) -> String {
        guard let firstName else { return "LOREEN" }
        let normalized = normalizeChallengeWord(firstName)
        guard normalized.count >= 2 else { return "LOREEN" }
        return String(normalized.prefix(10))
    }

    // MARK: - Geometry Helpers (in SVG 0..100 x 0..120 space)
    private static func pt(_ sx: Double, _ sy: Double) -> LoreenPoint {
        LoreenPoint(x: sx / 100.0, y: sy / 120.0)
    }

    private static func circle(cx: Double, cy: Double, r: Double, steps: Int = 24) -> [LoreenPoint] {
        ellipse(cx: cx, cy: cy, rx: r, ry: r, steps: steps)
    }

    private static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, steps: Int = 24) -> [LoreenPoint] {
        (0...steps).map { k in
            let a = (2.0 * Double.pi * Double(k)) / Double(steps)
            return pt(cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    private static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, steps: Int = 8) -> [LoreenPoint] {
        (0...steps).map { k in
            let t = Double(k) / Double(steps)
            return pt(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
        }
    }

    private static func cubic(_ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double), _ p3: (Double, Double), steps: Int = 14) -> [LoreenPoint] {
        (0...steps).map { k in
            let t = Double(k) / Double(steps)
            let mt = 1.0 - t
            let x = mt * mt * mt * p0.0 + 3 * mt * mt * t * p1.0 + 3 * mt * t * t * p2.0 + t * t * t * p3.0
            let y = mt * mt * mt * p0.1 + 3 * mt * mt * t * p1.1 + 3 * mt * t * t * p2.1 + t * t * t * p3.1
            return pt(x, y)
        }
    }

    private static func arch(topSweep: Bool) -> [LoreenPoint] {
        if topSweep {
            // U, V, W: M 20 98 V 52 A 30 30 0 0 1 80 52 V 98
            var pts = line(20, 98, 20, 52, steps: 6)
            for k in 1...15 {
                let a = Double.pi + (Double.pi * Double(k)) / 16.0
                pts.append(pt(50 + 30 * cos(a), 52 + 30 * sin(a)))
            }
            pts.append(contentsOf: line(80, 52, 80, 98, steps: 6))
            return pts
        } else {
            // Y cup: M 22 22 V 34 A 28 28 0 0 0 78 34 V 22
            var pts = line(22, 22, 22, 34, steps: 3)
            for k in 1...15 {
                let a = Double.pi - (Double.pi * Double(k)) / 16.0
                pts.append(pt(50 + 28 * cos(a), 34 + 28 * sin(a)))
            }
            pts.append(contentsOf: line(78, 34, 78, 22, steps: 3))
            return pts
        }
    }

    public static let allGlyphs: [LoreenGlyphDefinition] = [
        LoreenGlyphDefinition(
            id: "A", origin: .original, family: "Radial (Vowel)",
            summary: "Empty circle — root of the radial vowel family",
            strokes: [circle(cx: 50, cy: 60, r: 38)]
        ),
        LoreenGlyphDefinition(
            id: "B", origin: .original, family: "Disguised Latin",
            summary: "Fluid 2-curve loop",
            strokes: [
                line(24, 24, 62, 24, steps: 5)
                + cubic((62, 24), (82, 24), (84, 52), (56, 58), steps: 10)
                + line(56, 58, 42, 62, steps: 3)
                + cubic((42, 62), (16, 68), (18, 96), (38, 96), steps: 10)
                + line(38, 96, 78, 96, steps: 5)
            ]
        ),
        LoreenGlyphDefinition(
            id: "C", origin: .original, family: "Bars & Rungs",
            summary: "Open twin-pillar frame (0 rungs)",
            strokes: [line(20, 22, 80, 22), line(20, 98, 80, 98), line(37, 22, 37, 98), line(63, 22, 63, 98)]
        ),
        LoreenGlyphDefinition(
            id: "D", origin: .original, family: "Bars & Rungs",
            summary: "Closed ladder frame with 3 rungs",
            strokes: [
                line(24, 22, 76, 22) + line(76, 22, 76, 98) + line(76, 98, 24, 98) + line(24, 98, 24, 22),
                line(24, 41, 76, 41), line(24, 60, 76, 60), line(24, 79, 76, 79)
            ]
        ),
        LoreenGlyphDefinition(
            id: "E", origin: .original, family: "Radial (Vowel)",
            summary: "Circle enclosing a 4-way cross",
            strokes: [circle(cx: 50, cy: 60, r: 38), line(12, 60, 88, 60), line(50, 22, 50, 98)]
        ),
        LoreenGlyphDefinition(
            id: "F", origin: .original, family: "Recalled (PDF)",
            summary: "Inverted triangle bisected by a full cross",
            strokes: [
                line(18, 22, 82, 22) + line(82, 22, 50, 96) + line(50, 96, 18, 22),
                line(50, 22, 50, 98), line(24, 58, 76, 58)
            ]
        ),
        LoreenGlyphDefinition(
            id: "G", origin: .completed, family: "Radial",
            summary: "Circle enclosing a diagonal X cross",
            strokes: [circle(cx: 50, cy: 60, r: 38), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9)]
        ),
        LoreenGlyphDefinition(
            id: "H", origin: .completed, family: "Radial",
            summary: "Two full-height adjacent touching loops (infinity)",
            strokes: [ellipse(cx: 26.5, cy: 60, rx: 23.5, ry: 38, steps: 20), ellipse(cx: 73.5, cy: 60, rx: 23.5, ry: 38, steps: 20)]
        ),
        LoreenGlyphDefinition(
            id: "I", origin: .original, family: "Radial / Cross",
            summary: "Bare Latin cross",
            strokes: [line(50, 22, 50, 98), line(28, 46, 72, 46)]
        ),
        LoreenGlyphDefinition(
            id: "J", origin: .original, family: "Architectural",
            summary: "Vertical spine with top-left & bottom-right flags",
            strokes: [
                line(20, 22, 50, 22) + line(50, 22, 50, 40) + line(50, 40, 20, 40) + line(20, 40, 20, 22),
                line(50, 40, 50, 80),
                line(50, 80, 80, 80) + line(80, 80, 80, 98) + line(80, 98, 50, 98) + line(50, 98, 50, 80)
            ]
        ),
        LoreenGlyphDefinition(
            id: "K", origin: .completed, family: "Architectural",
            summary: "Inverted L — wide top block with descending stem",
            strokes: [
                line(16, 22, 84, 22) + line(84, 22, 84, 48) + line(84, 48, 16, 48) + line(16, 48, 16, 22),
                line(40, 48, 40, 98) + line(40, 98, 60, 98) + line(60, 98, 60, 48)
            ]
        ),
        LoreenGlyphDefinition(
            id: "L", origin: .original, family: "Architectural",
            summary: "Pedestal / top-hat — wide base block with rising stem",
            strokes: [
                line(16, 72, 84, 72) + line(84, 72, 84, 98) + line(84, 98, 16, 98) + line(16, 98, 16, 72),
                line(40, 72, 40, 22) + line(40, 22, 60, 22) + line(60, 22, 60, 72)
            ]
        ),
        LoreenGlyphDefinition(
            id: "M", origin: .original, family: "Disguised Latin",
            summary: "M with crossed inner legs",
            strokes: [line(16, 98, 34, 22) + line(34, 22, 62, 98), line(38, 98, 66, 22) + line(66, 22, 84, 98)]
        ),
        LoreenGlyphDefinition(
            id: "N", origin: .original, family: "Symmetric",
            summary: "Opposing arches meeting at the center",
            strokes: [
                cubic((20, 22), (20, 56), (36, 60), (50, 60), steps: 8) + cubic((50, 60), (64, 60), (80, 56), (80, 22), steps: 8),
                cubic((20, 98), (20, 64), (36, 60), (50, 60), steps: 8) + cubic((50, 60), (64, 60), (80, 64), (80, 98), steps: 8)
            ]
        ),
        LoreenGlyphDefinition(
            id: "O", origin: .original, family: "Radial (Vowel)",
            summary: "Bare 8-ray star",
            strokes: [line(50, 22, 50, 98), line(12, 60, 88, 60), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9)]
        ),
        LoreenGlyphDefinition(
            id: "P", origin: .completed, family: "Mirror Pair",
            summary: "Horizontal mirror of R (triangle pointing left)",
            strokes: [line(22, 22, 22, 98), line(78, 22, 78, 98), line(78, 22, 22, 60) + line(22, 60, 78, 98)]
        ),
        LoreenGlyphDefinition(
            id: "Q", origin: .original, family: "Radial",
            summary: "Circle enclosing an 8-ray star (A + O)",
            strokes: [circle(cx: 50, cy: 60, r: 38), line(50, 22, 50, 98), line(12, 60, 88, 60), line(23.1, 33.1, 76.9, 86.9), line(76.9, 33.1, 23.1, 86.9)]
        ),
        LoreenGlyphDefinition(
            id: "R", origin: .original, family: "Mirror Pair",
            summary: "Triangle pointing right between vertical rails",
            strokes: [line(22, 22, 22, 98), line(78, 22, 78, 98), line(22, 22, 78, 60) + line(78, 60, 22, 98)]
        ),
        LoreenGlyphDefinition(
            id: "S", origin: .completed, family: "Hourglass",
            summary: "Empty vertical hourglass",
            strokes: [line(20, 22, 80, 22) + line(80, 22, 20, 98) + line(20, 98, 80, 98) + line(80, 98, 20, 22)]
        ),
        LoreenGlyphDefinition(
            id: "T", origin: .completed, family: "Crosses",
            summary: "Cross of Lorraine (paired with I)",
            strokes: [line(50, 22, 50, 98), line(32, 42, 68, 42), line(22, 62, 78, 62)]
        ),
        LoreenGlyphDefinition(
            id: "U", origin: .original, family: "Arch & Bars",
            summary: "Inverted open arch (0 crossbars)",
            strokes: [arch(topSweep: true)]
        ),
        LoreenGlyphDefinition(
            id: "V", origin: .original, family: "Arch & Bars",
            summary: "Inverted arch with 1 crossbar",
            strokes: [arch(topSweep: true), line(20, 60, 80, 60)]
        ),
        LoreenGlyphDefinition(
            id: "W", origin: .original, family: "Arch & Bars",
            summary: "Inverted arch with 2 crossbars",
            strokes: [arch(topSweep: true), line(20, 52, 80, 52), line(20, 72, 80, 72)]
        ),
        LoreenGlyphDefinition(
            id: "X", origin: .original, family: "Symmetric",
            summary: "Curved vertical vesica with 4 flared ends",
            strokes: [
                cubic((20, 22), (80, 34), (80, 86), (20, 98), steps: 14),
                cubic((80, 22), (20, 34), (20, 86), (80, 98), steps: 14)
            ]
        ),
        LoreenGlyphDefinition(
            id: "Y", origin: .completed, family: "Arch & Bars",
            summary: "Chalice / trident with tall inner vertical stem",
            strokes: [arch(topSweep: false), line(50, 30, 50, 98)]
        ),
        LoreenGlyphDefinition(
            id: "Z", origin: .completed, family: "Hourglass",
            summary: "90-degree rotation of S (empty horizontal bowtie)",
            strokes: [line(16, 22, 16, 98) + line(16, 98, 84, 22) + line(84, 22, 84, 98) + line(84, 98, 16, 22)]
        )
    ]

    public static func definition(for letter: Character) -> LoreenGlyphDefinition? {
        let up = Character(String(letter).uppercased())
        return allGlyphs.first { $0.id == up }
    }
}
