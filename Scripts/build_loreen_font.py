#!/usr/bin/env python3
"""
Builds Loreen-Regular.ttf from Art/Loreen/loreen_glyphs.json.
Uses shapely for clean monoline round-cap stroke-to-outline expansion
and fontTools to emit a valid TrueType font with monocase + Romanian diacritic cmap.
"""

import json
import math
import os
import re
import shutil
from typing import List, Optional, Tuple

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from shapely.geometry import LineString, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC_PATH = os.path.join(ROOT, "Art", "Loreen", "loreen_glyphs.json")
ART_TTF_PATH = os.path.join(ROOT, "Art", "Loreen", "Loreen-Regular.ttf")
CORE_TTF_PATH = os.path.join(ROOT, "DailyCore", "Sources", "DailyCore", "Resources", "Fonts", "Loreen-Regular.ttf")
ANDROID_TTF_PATH = os.path.join(ROOT, "Android", "app", "src", "main", "res", "font", "loreen_regular.ttf")
WINUI_TTF_PATH = os.path.join(ROOT, "WinUI", "Daily.WinUI", "Assets", "Fonts", "Loreen-Regular.ttf")

UNITS_PER_EM = 1000
ASCENT = 820
DESCENT = -180
CAP_HEIGHT = 745
X_HEIGHT = 745
DEFAULT_ADVANCE = 860
HALF_STROKE = 33.0


def svg_to_font_xy(sx: float, sy: float, advance: int = DEFAULT_ADVANCE) -> Tuple[float, float]:
    cx = advance / 2.0
    fx = cx + (sx - 50.0) * 9.5
    fy = (98.0 - sy) * 9.8
    return fx, fy


def sample_cubic(p0, p1, p2, p3, steps=20):
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = (mt ** 3) * p0[0] + 3 * (mt ** 2) * t * p1[0] + 3 * mt * (t ** 2) * p2[0] + (t ** 3) * p3[0]
        y = (mt ** 3) * p0[1] + 3 * (mt ** 2) * t * p1[1] + 3 * mt * (t ** 2) * p2[1] + (t ** 3) * p3[1]
        pts.append((x, y))
    return pts


def sample_svg_arc(p0, rx, ry, x_axis_rotation, large_arc_flag, sweep_flag, p1, steps=28):
    # W3C SVG F.6.5 / F.6.6 implementation
    x1, y1 = p0
    x2, y2 = p1
    if rx == 0 or ry == 0:
        return [p1]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(x_axis_rotation)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)

    dx2 = (x1 - x2) / 2.0
    dy2 = (y1 - y2) / 2.0
    x1p = cos_phi * dx2 + sin_phi * dy2
    y1p = -sin_phi * dx2 + cos_phi * dy2

    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1.0:
        s = math.sqrt(lam)
        rx *= s
        ry *= s

    rx2, ry2 = rx ** 2, ry ** 2
    x1p2, y1p2 = x1p ** 2, y1p ** 2
    denom = rx2 * y1p2 + ry2 * x1p2
    num = max(0.0, rx2 * ry2 - denom)
    factor = math.sqrt(num / denom) if denom > 1e-9 else 0.0
    if large_arc_flag == sweep_flag:
        factor = -factor

    cxp = factor * (rx * y1p / ry)
    cyp = factor * (-ry * x1p / rx)

    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2.0
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2.0

    def vec_angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        mag = math.hypot(ux, uy) * math.hypot(vx, vy)
        c = max(-1.0, min(1.0, dot / mag)) if mag > 1e-9 else 1.0
        ang = math.acos(c)
        if ux * vy - uy * vx < 0:
            ang = -ang
        return ang

    ux = (x1p - cxp) / rx
    uy = (y1p - cyp) / ry
    vx = (-x1p - cxp) / rx
    vy = (-y1p - cyp) / ry

    theta1 = vec_angle(1.0, 0.0, ux, uy)
    dtheta = vec_angle(ux, uy, vx, vy)
    if sweep_flag == 0 and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep_flag == 1 and dtheta < 0:
        dtheta += 2 * math.pi

    pts = []
    for i in range(1, steps + 1):
        t = theta1 + dtheta * (i / steps)
        xp = rx * math.cos(t)
        yp = ry * math.sin(t)
        x = cos_phi * xp - sin_phi * yp + cx
        y = sin_phi * xp + cos_phi * yp + cy
        pts.append((x, y))
    return pts


def parse_svg_path_to_polylines(d: str) -> List[List[Tuple[float, float]]]:
    tokens = re.findall(r"[A-Za-z]|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", d)
    polylines: List[List[Tuple[float, float]]] = []
    current: List[Tuple[float, float]] = []
    cx, cy = 0.0, 0.0
    sx, sy = 0.0, 0.0
    cmd = None
    i = 0

    def next_float():
        nonlocal i
        val = float(tokens[i])
        i += 1
        return val

    while i < len(tokens):
        tok = tokens[i]
        if tok.isalpha():
            cmd = tok
            i += 1
            if cmd in ("Z", "z"):
                if current:
                    current.append((sx, sy))
                    cx, cy = sx, sy
                    polylines.append(current)
                    current = []
                continue
        if cmd == "M":
            if current:
                polylines.append(current)
            cx, cy = next_float(), next_float()
            sx, sy = cx, cy
            current = [(cx, cy)]
            cmd = "L"
        elif cmd == "L":
            cx, cy = next_float(), next_float()
            current.append((cx, cy))
        elif cmd == "H":
            cx = next_float()
            current.append((cx, cy))
        elif cmd == "V":
            cy = next_float()
            current.append((cx, cy))
        elif cmd == "C":
            p1 = (next_float(), next_float())
            p2 = (next_float(), next_float())
            p3 = (next_float(), next_float())
            current.extend(sample_cubic((cx, cy), p1, p2, p3))
            cx, cy = p3
        elif cmd == "A":
            rx = next_float()
            ry = next_float()
            rot = next_float()
            large = int(next_float())
            sweep = int(next_float())
            nx, ny = next_float(), next_float()
            current.extend(sample_svg_arc((cx, cy), rx, ry, rot, large, sweep, (nx, ny)))
            cx, cy = nx, ny
        else:
            raise ValueError(f"Unsupported SVG command: {cmd}")

    if current:
        polylines.append(current)
    return polylines


def circle_to_polyline(cx: float, cy: float, rx: float, ry: Optional[float] = None, steps: int = 48) -> List[Tuple[float, float]]:
    eff_ry = rx if ry is None else ry
    pts = []
    for k in range(steps + 1):
        a = 2.0 * math.pi * k / steps
        pts.append((cx + rx * math.cos(a), cy + eff_ry * math.sin(a)))
    return pts


def signed_area(coords: List[Tuple[int, int]]) -> float:
    area = 0.0
    n = len(coords)
    for idx in range(n):
        x1, y1 = coords[idx]
        x2, y2 = coords[(idx + 1) % n]
        area += (x1 * y2 - x2 * y1)
    return 0.5 * area


def dedupe_int_ring(ring_coords) -> List[Tuple[int, int]]:
    pts = [(int(round(x)), int(round(y))) for x, y in ring_coords]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    cleaned: List[Tuple[int, int]] = []
    for p in pts:
        if not cleaned or cleaned[-1] != p:
            cleaned.append(p)
    if len(cleaned) > 1 and cleaned[0] == cleaned[-1]:
        cleaned = cleaned[:-1]
    return cleaned


def strokes_to_tt_glyph(polylines_svg: List[List[Tuple[float, float]]], advance: int, half_stroke: float = HALF_STROKE):
    buffered = []
    for poly in polylines_svg:
        f_pts = [svg_to_font_xy(sx, sy, advance) for sx, sy in poly]
        if len(f_pts) < 2:
            continue
        geom = LineString(f_pts).buffer(half_stroke, cap_style="round", join_style="round", quad_segs=8)
        if not geom.is_empty:
            buffered.append(geom)

    if not buffered:
        pen = TTGlyphPen(None)
        return pen.glyph()

    merged = unary_union(buffered).simplify(1.2, preserve_topology=True)
    polys = []
    if merged.geom_type == "Polygon":
        polys = [merged]
    elif merged.geom_type == "MultiPolygon":
        polys = list(merged.geoms)
    else:
        for g in getattr(merged, "geoms", []):
            if g.geom_type == "Polygon":
                polys.append(g)

    pen = TTGlyphPen(None)
    for poly in polys:
        p_oriented = orient(poly, sign=-1.0)
        ext = dedupe_int_ring(p_oriented.exterior.coords)
        if len(ext) >= 3:
            if signed_area(ext) > 0:
                ext = list(reversed(ext))
            pen.moveTo(ext[0])
            for pt in ext[1:]:
                pen.lineTo(pt)
            pen.closePath()

        for interior in p_oriented.interiors:
            hole = dedupe_int_ring(interior.coords)
            if len(hole) >= 3:
                if signed_area(hole) < 0:
                    hole = list(reversed(hole))
                pen.moveTo(hole[0])
                for pt in hole[1:]:
                    pen.lineTo(pt)
                pen.closePath()

    return pen.glyph()


# Geometric monoline digits & TagDoS DSL punctuation in SVG 100x120 coordinates
EXTRA_GLYPHS = {
    "zero": ("0", 680, [], ["M 30 30 H 70 V 90 H 30 Z M 32 88 L 68 32"]),
    "one": ("1", 560, [], ["M 36 38 L 52 24 V 94 M 34 94 H 70"]),
    "two": ("2", 680, [], ["M 26 40 C 26 20 74 20 74 42 C 74 60 26 74 26 94 H 74"]),
    "three": ("3", 680, [], ["M 26 28 H 72 L 46 54 C 74 54 76 94 48 94 C 34 94 26 88 24 82"]),
    "four": ("4", 680, [], ["M 64 94 V 24 L 24 72 H 76"]),
    "five": ("5", 680, [], ["M 72 24 H 30 V 54 C 72 50 76 94 46 94 C 34 94 26 88 24 82"]),
    "six": ("6", 680, [], ["M 66 26 C 32 26 26 56 26 74 C 26 94 74 94 74 72 C 74 54 28 54 26 70"]),
    "seven": ("7", 680, [], ["M 24 24 H 76 L 40 94"]),
    "eight": ("8", 680, [{ "cx": 50, "cy": 41, "r": 17 }, { "cx": 50, "cy": 77, "r": 19 }], []),
    "nine": ("9", 680, [], ["M 34 92 C 68 92 74 62 74 44 C 74 24 26 24 26 46 C 26 64 72 64 74 48"]),
    "slash": ("/", 560, [], ["M 68 20 L 32 98"]),
    "ampersand": ("&", 760, [], ["M 74 88 L 32 48 C 24 38 30 22 46 22 C 60 22 64 36 52 46 L 28 66 C 18 76 26 96 46 96 C 60 96 70 86 76 70"]),
    "dollar": ("$", 680, [], ["M 50 18 V 102 M 70 34 C 58 24 30 26 30 42 C 30 58 72 58 72 76 C 72 92 42 94 28 84"]),
    "euro": ("€", 680, [], ["M 74 34 C 56 20 30 30 30 60 C 30 90 56 100 74 86 M 20 52 H 60 M 20 68 H 56"]),
    "exclam": ("!", 420, [], ["M 50 22 V 72 M 50 92 V 95"]),
    "question": ("?", 620, [], ["M 30 36 C 30 20 70 20 70 40 C 70 54 50 58 50 72 M 50 92 V 95"]),
    "period": (".", 360, [], ["M 50 92 V 95"]),
    "comma": (",", 380, [], ["M 52 88 L 44 104"]),
    "colon": (":", 380, [], ["M 50 48 V 51 M 50 90 V 93"]),
    "semicolon": (";", 380, [], ["M 50 48 V 51 M 52 88 L 44 104"]),
    "hyphen": ("-", 520, [], ["M 30 60 H 70"]),
    "endash": ("–", 620, [], ["M 22 60 H 78"]),
    "emdash": ("—", 780, [], ["M 12 60 H 88"]),
    "parenleft": ("(", 460, [], ["M 62 20 C 38 36 38 84 62 100"]),
    "parenright": (")", 460, [], ["M 38 20 C 62 36 62 84 38 100"]),
    "plus": ("+", 640, [], ["M 50 36 V 84 M 26 60 H 74"]),
    "numbersign": ("#", 700, [], ["M 38 24 L 30 96 M 68 24 L 60 96 M 20 46 H 80 M 18 72 H 78"]),
    "percent": ("%", 760, [{ "cx": 30, "cy": 36, "r": 10 }, { "cx": 70, "cy": 84, "r": 10 }], ["M 74 24 L 26 96"]),
    "at": ("@", 800, [], ["M 64 60 A 14 14 0 1 1 36 60 A 14 14 0 1 1 64 60 V 72 C 64 82 78 80 80 62 C 82 32 62 22 46 22 C 24 22 16 42 16 62 C 16 86 34 98 60 94"]),
    "underscore": ("_", 640, [], ["M 18 98 H 82"]),
    "quotesingle": ("'", 340, [], ["M 50 22 V 42"]),
    "quotedbl": ('"', 500, [], ["M 36 22 V 42 M 64 22 V 42"]),
    "bracketleft": ("[", 460, [], ["M 62 20 H 38 V 100 H 62"]),
    "bracketright": ("]", 460, [], ["M 38 20 H 62 V 100 H 38"]),
    "asterisk": ("*", 580, [], ["M 50 30 V 66 M 34 40 L 66 56 M 66 40 L 34 56"]),
    "bullet": ("•", 500, [{ "cx": 50, "cy": 60, "r": 5 }], []),
    "arrowright": ("→", 760, [], ["M 18 60 H 82 M 62 40 L 82 60 L 62 80"])
}


def build_font():
    with open(SPEC_PATH, "r", encoding="utf-8") as f:
        spec = json.load(f)

    glyph_order = [".notdef", "space"]
    glyphs = {}
    metrics = {}

    # .notdef
    notdef_pen = TTGlyphPen(None)
    notdef_pen.moveTo((100, 0))
    notdef_pen.lineTo((100, 700))
    notdef_pen.lineTo((600, 700))
    notdef_pen.lineTo((600, 0))
    notdef_pen.closePath()
    notdef_pen.moveTo((180, 80))
    notdef_pen.lineTo((520, 80))
    notdef_pen.lineTo((520, 620))
    notdef_pen.lineTo((180, 620))
    notdef_pen.closePath()
    glyphs[".notdef"] = notdef_pen.glyph()
    metrics[".notdef"] = (700, 100)

    # space
    glyphs["space"] = TTGlyphPen(None).glyph()
    metrics["space"] = (420, 0)

    cmap = {0x0020: "space", 0x00A0: "space"}

    # 26 Loreen letters
    for item in spec["letters"]:
        ch = item["char"]
        adv = item.get("advance", DEFAULT_ADVANCE)
        polylines = []
        for c in item.get("circles", []):
            polylines.append(circle_to_polyline(c["cx"], c["cy"], c.get("rx", c.get("r")), c.get("ry", c.get("r"))))
        for p in item.get("paths", []):
            polylines.extend(parse_svg_path_to_polylines(p))

        g = strokes_to_tt_glyph(polylines, adv)
        glyph_order.append(ch)
        glyphs[ch] = g
        lsb = min((x for x, _ in g.coordinates), default=0) if g.numberOfContours > 0 else 0
        metrics[ch] = (adv, lsb)

        code_up = ord(ch)
        code_lo = ord(ch.lower())
        cmap[code_up] = ch
        cmap[code_lo] = ch

    # Romanian diacritics + common Latin accents in cmap
    diacritic_map = {
        "A": "ĂăÂâÁÀÄáàäÅå",
        "C": "Çç",
        "E": "ÉÈÊËéèêë",
        "I": "ÎîÍÌÏíìï",
        "N": "Ññ",
        "O": "ÓÒÔÖóòôö",
        "S": "ȘșŞş",
        "T": "ȚțŢţ",
        "U": "ÚÙÛÜúùûü",
    }
    for base, chars in diacritic_map.items():
        for c in chars:
            cmap[ord(c)] = base

    # Digits and DSL/Note punctuation
    for gname, (char_str, adv, circles, paths) in EXTRA_GLYPHS.items():
        polylines = []
        for c in circles:
            polylines.append(circle_to_polyline(c["cx"], c["cy"], c["r"]))
        for p in paths:
            polylines.extend(parse_svg_path_to_polylines(p))
        g = strokes_to_tt_glyph(polylines, adv, half_stroke=28.0)
        glyph_order.append(gname)
        glyphs[gname] = g
        lsb = min((x for x, _ in g.coordinates), default=0) if g.numberOfContours > 0 else 0
        metrics[gname] = (adv, lsb)
        cmap[ord(char_str)] = gname

    fb = FontBuilder(UNITS_PER_EM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable({
        "copyright": "Copyright (c) 2026 Daily / Mihai",
        "familyName": "Loreen",
        "styleName": "Regular",
        "uniqueFontIdentifier": "Loreen-Regular-1.0.0",
        "fullName": "Loreen Regular",
        "psName": "Loreen-Regular",
        "version": "Version 1.000",
    })
    fb.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        sTypoLineGap=100,
        usWinAscent=ASCENT + 40,
        usWinDescent=abs(DESCENT) + 40,
        sxHeight=X_HEIGHT,
        sCapHeight=CAP_HEIGHT,
    )
    fb.setupPost()

    os.makedirs(os.path.dirname(ART_TTF_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(CORE_TTF_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(ANDROID_TTF_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(WINUI_TTF_PATH), exist_ok=True)
    fb.save(ART_TTF_PATH)
    shutil.copy2(ART_TTF_PATH, CORE_TTF_PATH)
    shutil.copy2(ART_TTF_PATH, ANDROID_TTF_PATH)
    shutil.copy2(ART_TTF_PATH, WINUI_TTF_PATH)
    print(f"Built {ART_TTF_PATH} ({os.path.getsize(ART_TTF_PATH)} bytes) and copied to Core/Android/WinUI")
    print(f"Total glyphs: {len(glyph_order)}, cmap entries: {len(cmap)}")


if __name__ == "__main__":
    build_font()
