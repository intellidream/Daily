package com.intellidream.daily.glance

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

enum class WidgetIconType {
    FLAME,
    DROP,
    MOON,
    MOON_STARS,
    MOON_ZZZ,
    WALLET,
    CREDIT_CARD,
    CHECKLIST,
    BELL,
    SPARKLES,
    HEART,
    ECG,
    APPLE_WATCH,
    STAR_FILL,
    CHEVRON_RIGHT,
    ARROW_RIGHT,
    ARROW_UP_RIGHT_CIRCLE
}

/**
 * High-performance, anti-aliased Canvas drawer that produces crisp, high-DPI bitmaps
 * for Jetpack Glance AppWidgets, achieving 100% 1:1 visual parity with iOS WidgetKit.
 */
object WidgetVisualGraphics {

    // =========================================================================
    // MARK: - Color & Formatting Helpers
    // =========================================================================

    fun getLungHealthColor(countToday: Int, baseline: Int): Int {
        val base = max(baseline, 1)
        val ratio = countToday.toDouble() / base.toDouble()
        return if (countToday == 0) {
            Color.rgb(255, 107, 139) // Healthy Pink
        } else if (ratio <= 0.35) {
            val t = ratio / 0.35
            Color.rgb(
                (255 - t * (255 - 215)).toInt(),
                (107 + t * (125 - 107)).toInt(),
                (139 + t * (145 - 139)).toInt()
            )
        } else if (ratio <= 0.75) {
            val t = (ratio - 0.35) / 0.40
            Color.rgb(
                (215 - t * (215 - 120)).toInt(),
                (125 - t * (125 - 113)).toInt(),
                (145 - t * (145 - 108)).toInt()
            )
        } else if (ratio <= 1.0) {
            val t = (ratio - 0.75) / 0.25
            Color.rgb(
                (120 - t * (120 - 75)).toInt(),
                (113 - t * (113 - 85)).toInt(),
                (108 - t * (108 - 99)).toInt()
            )
        } else {
            val t = min((ratio - 1.0) / 0.5, 1.0)
            Color.rgb(
                (75 - t * (75 - 39)).toInt(),
                (85 - t * (85 - 39)).toInt(),
                (99 - t * (99 - 42)).toInt()
            )
        }
    }

    fun getSmokeRingColor(countToday: Int, baseline: Int): Int {
        val base = max(baseline, 1)
        val ratio = countToday.toDouble() / base.toDouble()
        return when {
            countToday == 0 -> Color.parseColor("#00E676") // accentGreen
            ratio < 0.4 -> Color.parseColor("#00E676")
            ratio < 0.75 -> Color.parseColor("#FFB800") // accentAmber
            ratio <= 1.0 -> Color.parseColor("#F97316") // accentOrange
            else -> Color.parseColor("#EF4444") // accentRed
        }
    }

    fun formatCompactTimeAgo(lastDateMillis: Long?): String {
        if (lastDateMillis == null || lastDateMillis <= 0L) return "0s"
        val diffSec = max(0L, (System.currentTimeMillis() - lastDateMillis) / 1000L)
        val hours = diffSec / 3600
        val minutes = (diffSec % 3600) / 60
        val seconds = diffSec % 60
        return when {
            hours > 0 -> "${hours}h"
            minutes > 0 -> "${minutes}m"
            else -> "${seconds}s"
        }
    }

    fun formatCompactNumber(amount: Double): String {
        return when {
            amount >= 1_000_000 -> String.format("%.1fM", amount / 1_000_000)
            amount >= 1_000 -> {
                val thousands = amount / 1_000
                if (thousands % 1.0 == 0.0) {
                    String.format("%.0fK", thousands)
                } else {
                    String.format("%.1fK", thousands)
                }
            }
            else -> String.format("%.0f", amount)
        }
    }

    fun formatCompactEUR(amount: Double): String {
        return when {
            amount >= 1_000_000 -> String.format("%.1fM €", amount / 1_000_000)
            amount >= 10_000 -> {
                val thousands = amount / 1_000
                if (thousands % 1.0 == 0.0) {
                    String.format("%.0fK €", thousands)
                } else {
                    String.format("%.1fK €", thousands)
                }
            }
            amount >= 1_000 -> String.format("%.1fK €", amount / 1_000)
            else -> String.format("%.0f €", amount)
        }
    }

    fun formatCompactIntegerEUR(amount: Double): String {
        return when {
            amount >= 1_000_000 -> "${(amount / 1_000_000).roundToInt()}M"
            amount >= 1_000 -> "${(amount / 1_000).roundToInt()}k"
            else -> "${amount.roundToInt()}"
        }
    }

    // =========================================================================
    // MARK: - Exact Vector Icons & Watermarks
    // =========================================================================

    fun createVectorIconBitmap(
        icon: WidgetIconType,
        sizePx: Int = 48,
        colorInt: Int = Color.WHITE,
        opacity: Float = 1.0f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = colorInt
            alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
        }

        val w = sizePx.toFloat()
        val h = sizePx.toFloat()

        when (icon) {
            WidgetIconType.FLAME -> {
                val path = Path().apply {
                    moveTo(w * 0.50f, h * 0.94f)
                    cubicTo(w * 0.20f, h * 0.94f, w * 0.12f, h * 0.72f, w * 0.12f, h * 0.58f)
                    cubicTo(w * 0.12f, h * 0.40f, w * 0.26f, h * 0.26f, w * 0.38f, h * 0.22f)
                    cubicTo(w * 0.36f, h * 0.32f, w * 0.40f, h * 0.38f, w * 0.46f, h * 0.38f)
                    cubicTo(w * 0.44f, h * 0.24f, w * 0.52f, h * 0.08f, w * 0.62f, h * 0.06f)
                    cubicTo(w * 0.58f, h * 0.20f, w * 0.66f, h * 0.34f, w * 0.74f, h * 0.40f)
                    cubicTo(w * 0.78f, h * 0.32f, w * 0.80f, h * 0.26f, w * 0.80f, h * 0.20f)
                    cubicTo(w * 0.88f, h * 0.34f, w * 0.88f, h * 0.54f, w * 0.88f, h * 0.62f)
                    cubicTo(w * 0.88f, h * 0.80f, w * 0.76f, h * 0.94f, w * 0.50f, h * 0.94f)
                    close()
                }
                canvas.drawPath(path, paint)
            }
            WidgetIconType.DROP -> {
                val path = Path().apply {
                    moveTo(w * 0.50f, h * 0.08f)
                    cubicTo(w * 0.48f, h * 0.18f, w * 0.16f, h * 0.54f, w * 0.16f, h * 0.68f)
                    cubicTo(w * 0.16f, h * 0.84f, w * 0.32f, h * 0.94f, w * 0.50f, h * 0.94f)
                    cubicTo(w * 0.68f, h * 0.94f, w * 0.84f, h * 0.84f, w * 0.84f, h * 0.68f)
                    cubicTo(w * 0.84f, h * 0.54f, w * 0.52f, h * 0.18f, w * 0.50f, h * 0.08f)
                    close()
                }
                canvas.drawPath(path, paint)
            }
            WidgetIconType.MOON -> {
                val path = Path().apply {
                    moveTo(w * 0.68f, h * 0.12f)
                    cubicTo(w * 0.36f, h * 0.14f, w * 0.14f, h * 0.38f, w * 0.14f, h * 0.66f)
                    cubicTo(w * 0.14f, h * 0.84f, w * 0.28f, h * 0.95f, w * 0.52f, h * 0.95f)
                    cubicTo(w * 0.72f, h * 0.95f, w * 0.86f, h * 0.82f, w * 0.88f, h * 0.68f)
                    cubicTo(w * 0.70f, h * 0.72f, w * 0.48f, h * 0.62f, w * 0.48f, h * 0.38f)
                    cubicTo(w * 0.48f, h * 0.24f, w * 0.58f, h * 0.14f, w * 0.68f, h * 0.12f)
                    close()
                }
                canvas.drawPath(path, paint)
            }
            WidgetIconType.MOON_STARS -> {
                // Crescent Moon on left
                val moonPath = Path().apply {
                    moveTo(w * 0.54f, h * 0.15f)
                    cubicTo(w * 0.28f, h * 0.18f, w * 0.12f, h * 0.40f, w * 0.12f, h * 0.66f)
                    cubicTo(w * 0.12f, h * 0.84f, w * 0.26f, h * 0.94f, w * 0.48f, h * 0.94f)
                    cubicTo(w * 0.68f, h * 0.94f, w * 0.78f, h * 0.84f, w * 0.80f, h * 0.72f)
                    cubicTo(w * 0.62f, h * 0.74f, w * 0.42f, h * 0.64f, w * 0.42f, h * 0.40f)
                    cubicTo(w * 0.42f, h * 0.26f, w * 0.48f, h * 0.18f, w * 0.54f, h * 0.15f)
                    close()
                }
                canvas.drawPath(moonPath, paint)

                // 4-pointed Star at Top-Right
                drawFourPointStar(canvas, paint, w * 0.78f, h * 0.26f, w * 0.14f)
                // Small 4-pointed Star
                drawFourPointStar(canvas, paint, w * 0.64f, h * 0.48f, w * 0.08f)
            }
            WidgetIconType.MOON_ZZZ -> {
                val moonPath = Path().apply {
                    moveTo(w * 0.46f, h * 0.18f)
                    cubicTo(w * 0.22f, h * 0.20f, w * 0.10f, h * 0.42f, w * 0.10f, h * 0.66f)
                    cubicTo(w * 0.10f, h * 0.84f, w * 0.24f, h * 0.94f, w * 0.44f, h * 0.94f)
                    cubicTo(w * 0.62f, h * 0.94f, w * 0.72f, h * 0.84f, w * 0.74f, h * 0.74f)
                    cubicTo(w * 0.56f, h * 0.75f, w * 0.38f, h * 0.64f, w * 0.38f, h * 0.42f)
                    cubicTo(w * 0.38f, h * 0.28f, w * 0.42f, h * 0.20f, w * 0.46f, h * 0.18f)
                    close()
                }
                canvas.drawPath(moonPath, paint)

                // Zzz shapes
                drawZLetter(canvas, paint, w * 0.74f, h * 0.16f, w * 0.16f)
                drawZLetter(canvas, paint, w * 0.64f, h * 0.38f, w * 0.11f)
            }
            WidgetIconType.WALLET -> {
                val body = RectF(w * 0.08f, h * 0.20f, w * 0.92f, h * 0.82f)
                canvas.drawRoundRect(body, w * 0.12f, w * 0.12f, paint)

                // Clasp flap on right
                val flap = RectF(w * 0.62f, h * 0.36f, w * 0.96f, h * 0.66f)
                val flapPaint = Paint(paint).apply {
                    color = Color.WHITE
                    alpha = (opacity.coerceIn(0f, 1f) * 200).toInt()
                }
                canvas.drawRoundRect(flap, w * 0.08f, w * 0.08f, flapPaint)

                // Clasp dot
                val dotPaint = Paint(paint).apply {
                    color = colorInt
                    alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
                }
                canvas.drawCircle(w * 0.78f, h * 0.51f, w * 0.05f, dotPaint)
            }
            WidgetIconType.CREDIT_CARD -> {
                val body = RectF(w * 0.08f, h * 0.22f, w * 0.92f, h * 0.78f)
                canvas.drawRoundRect(body, w * 0.10f, w * 0.10f, paint)

                // Stripe
                val stripePaint = Paint(paint).apply {
                    color = Color.BLACK
                    alpha = (opacity.coerceIn(0f, 1f) * 160).toInt()
                }
                canvas.drawRect(w * 0.08f, h * 0.34f, w * 0.92f, h * 0.46f, stripePaint)

                // Chip or numbers
                val chipPaint = Paint(paint).apply {
                    color = Color.WHITE
                    alpha = (opacity.coerceIn(0f, 1f) * 180).toInt()
                }
                canvas.drawRoundRect(RectF(w * 0.18f, h * 0.56f, w * 0.34f, h * 0.68f), w * 0.03f, w * 0.03f, chipPaint)
            }
            WidgetIconType.CHECKLIST -> {
                // Outer clipboard body
                val body = RectF(w * 0.16f, h * 0.14f, w * 0.84f, h * 0.92f)
                canvas.drawRoundRect(body, w * 0.08f, w * 0.08f, paint)

                val innerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = max(2f, w * 0.06f)
                    color = Color.BLACK
                    alpha = (opacity.coerceIn(0f, 1f) * 140).toInt()
                    strokeCap = Paint.Cap.ROUND
                }

                // Check lines
                val y1 = h * 0.34f
                val y2 = h * 0.52f
                val y3 = h * 0.70f

                // Line 1
                canvas.drawLine(w * 0.38f, y1, w * 0.72f, y1, innerPaint)
                // Line 2
                canvas.drawLine(w * 0.38f, y2, w * 0.72f, y2, innerPaint)
                // Line 3
                canvas.drawLine(w * 0.38f, y3, w * 0.72f, y3, innerPaint)

                // Check dots/boxes
                val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.FILL
                    color = Color.BLACK
                    alpha = (opacity.coerceIn(0f, 1f) * 160).toInt()
                }
                canvas.drawCircle(w * 0.28f, y1, w * 0.035f, dotPaint)
                canvas.drawCircle(w * 0.28f, y2, w * 0.035f, dotPaint)
                canvas.drawCircle(w * 0.28f, y3, w * 0.035f, dotPaint)
            }
            WidgetIconType.BELL -> {
                val path = Path().apply {
                    moveTo(w * 0.50f, h * 0.12f)
                    cubicTo(w * 0.44f, h * 0.12f, w * 0.38f, h * 0.18f, w * 0.36f, h * 0.24f)
                    cubicTo(w * 0.32f, h * 0.38f, w * 0.24f, h * 0.58f, w * 0.16f, h * 0.72f)
                    lineTo(w * 0.84f, h * 0.72f)
                    cubicTo(w * 0.76f, h * 0.58f, w * 0.68f, h * 0.38f, w * 0.64f, h * 0.24f)
                    cubicTo(w * 0.62f, h * 0.18f, w * 0.56f, h * 0.12f, w * 0.50f, h * 0.12f)
                    close()
                }
                canvas.drawPath(path, paint)
                // Clapper
                canvas.drawCircle(w * 0.50f, h * 0.84f, w * 0.09f, paint)
            }
            WidgetIconType.SPARKLES -> {
                drawFourPointStar(canvas, paint, w * 0.42f, h * 0.46f, w * 0.36f)
                drawFourPointStar(canvas, paint, w * 0.76f, h * 0.24f, w * 0.16f)
            }
            WidgetIconType.HEART -> {
                val path = Path().apply {
                    moveTo(w * 0.50f, h * 0.88f)
                    cubicTo(w * 0.15f, h * 0.65f, w * 0.08f, h * 0.35f, w * 0.24f, h * 0.20f)
                    cubicTo(w * 0.36f, h * 0.10f, w * 0.46f, h * 0.18f, w * 0.50f, h * 0.26f)
                    cubicTo(w * 0.54f, h * 0.18f, w * 0.64f, h * 0.10f, w * 0.76f, h * 0.20f)
                    cubicTo(w * 0.92f, h * 0.35f, w * 0.85f, h * 0.65f, w * 0.50f, h * 0.88f)
                    close()
                }
                canvas.drawPath(path, paint)
            }
            WidgetIconType.ECG -> {
                val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = max(2.5f, w * 0.08f)
                    color = colorInt
                    alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
                val path = Path().apply {
                    moveTo(w * 0.06f, h * 0.52f)
                    lineTo(w * 0.28f, h * 0.52f)
                    lineTo(w * 0.36f, h * 0.42f)
                    lineTo(w * 0.44f, h * 0.72f)
                    lineTo(w * 0.54f, h * 0.16f)
                    lineTo(w * 0.64f, h * 0.82f)
                    lineTo(w * 0.72f, h * 0.52f)
                    lineTo(w * 0.94f, h * 0.52f)
                }
                canvas.drawPath(path, strokePaint)
            }
            WidgetIconType.APPLE_WATCH -> {
                // Straps
                canvas.drawRoundRect(RectF(w * 0.34f, h * 0.06f, w * 0.66f, h * 0.24f), w * 0.04f, w * 0.04f, paint)
                canvas.drawRoundRect(RectF(w * 0.34f, h * 0.76f, w * 0.66f, h * 0.94f), w * 0.04f, w * 0.04f, paint)
                // Case
                canvas.drawRoundRect(RectF(w * 0.22f, h * 0.20f, w * 0.78f, h * 0.80f), w * 0.14f, w * 0.14f, paint)
                // Dial crown
                canvas.drawRoundRect(RectF(w * 0.78f, h * 0.34f, w * 0.86f, h * 0.48f), w * 0.02f, w * 0.02f, paint)
            }
            WidgetIconType.STAR_FILL -> {
                val path = Path()
                val cx = w / 2f
                val cy = h / 2f
                val rOuter = w * 0.45f
                val rInner = w * 0.20f
                for (i in 0 until 10) {
                    val angle = (i * 36 - 90) * Math.PI / 180.0
                    val r = if (i % 2 == 0) rOuter else rInner
                    val x = cx + (r * Math.cos(angle)).toFloat()
                    val y = cy + (r * Math.sin(angle)).toFloat()
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                path.close()
                canvas.drawPath(path, paint)
            }
            WidgetIconType.CHEVRON_RIGHT -> {
                val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = max(2.5f, w * 0.12f)
                    color = colorInt
                    alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
                val path = Path().apply {
                    moveTo(w * 0.32f, h * 0.22f)
                    lineTo(w * 0.68f, h * 0.50f)
                    lineTo(w * 0.32f, h * 0.78f)
                }
                canvas.drawPath(path, strokePaint)
            }
            WidgetIconType.ARROW_RIGHT -> {
                val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = max(2.5f, w * 0.10f)
                    color = colorInt
                    alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
                canvas.drawLine(w * 0.16f, h * 0.50f, w * 0.80f, h * 0.50f, strokePaint)
                val head = Path().apply {
                    moveTo(w * 0.56f, h * 0.28f)
                    lineTo(w * 0.82f, h * 0.50f)
                    lineTo(w * 0.56f, h * 0.72f)
                }
                canvas.drawPath(head, strokePaint)
            }
            WidgetIconType.ARROW_UP_RIGHT_CIRCLE -> {
                val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = max(2f, w * 0.08f)
                    color = colorInt
                    alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
                canvas.drawCircle(w * 0.50f, h * 0.50f, w * 0.42f, strokePaint)
                canvas.drawLine(w * 0.35f, h * 0.65f, w * 0.65f, h * 0.35f, strokePaint)
                val head = Path().apply {
                    moveTo(w * 0.44f, h * 0.35f)
                    lineTo(w * 0.65f, h * 0.35f)
                    lineTo(w * 0.65f, h * 0.56f)
                }
                canvas.drawPath(head, strokePaint)
            }
        }

        return bitmap
    }

    private fun drawFourPointStar(canvas: Canvas, paint: Paint, cx: Float, cy: Float, radius: Float) {
        val path = Path().apply {
            moveTo(cx, cy - radius)
            quadTo(cx, cy, cx + radius, cy)
            quadTo(cx, cy, cx, cy + radius)
            quadTo(cx, cy, cx - radius, cy)
            quadTo(cx, cy, cx, cy - radius)
            close()
        }
        canvas.drawPath(path, paint)
    }

    private fun drawZLetter(canvas: Canvas, paint: Paint, x: Float, y: Float, size: Float) {
        val strokePaint = Paint(paint).apply {
            style = Paint.Style.STROKE
            strokeWidth = max(2f, size * 0.20f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val path = Path().apply {
            moveTo(x, y)
            lineTo(x + size, y)
            lineTo(x, y + size)
            lineTo(x + size, y + size)
        }
        canvas.drawPath(path, strokePaint)
    }

    // =========================================================================
    // MARK: - Anatomical Vector Lungs Shape & Bronchial Tree (Smokes)
    // =========================================================================

    fun createVectorLungsBitmap(
        widthPx: Int = 120,
        heightPx: Int = 120,
        lungColorInt: Int = Color.parseColor("#FF6B8B")
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val w = widthPx.toFloat()
        val h = heightPx.toFloat()

        val lungsPath = Path()
        // Trachea / Airway
        lungsPath.moveTo(w * 0.48f, h * 0.05f)
        lungsPath.lineTo(w * 0.52f, h * 0.05f)
        lungsPath.lineTo(w * 0.52f, h * 0.28f)
        lungsPath.lineTo(w * 0.48f, h * 0.28f)
        lungsPath.close()

        // Left Lung lobe
        lungsPath.moveTo(w * 0.46f, h * 0.29f)
        lungsPath.cubicTo(w * 0.30f, h * 0.26f, w * 0.12f, h * 0.38f, w * 0.12f, h * 0.52f)
        lungsPath.cubicTo(w * 0.12f, h * 0.72f, w * 0.22f, h * 0.88f, w * 0.38f, h * 0.90f)
        lungsPath.cubicTo(w * 0.42f, h * 0.80f, w * 0.44f, h * 0.52f, w * 0.46f, h * 0.38f)
        lungsPath.close()

        // Right Lung lobe
        lungsPath.moveTo(w * 0.54f, h * 0.29f)
        lungsPath.cubicTo(w * 0.70f, h * 0.26f, w * 0.88f, h * 0.38f, w * 0.88f, h * 0.52f)
        lungsPath.cubicTo(w * 0.88f, h * 0.72f, w * 0.78f, h * 0.88f, w * 0.62f, h * 0.90f)
        lungsPath.cubicTo(w * 0.58f, h * 0.80f, w * 0.56f, h * 0.52f, w * 0.54f, h * 0.38f)
        lungsPath.close()

        val lungsPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = lungColorInt
            alpha = 215
        }
        canvas.drawPath(lungsPath, lungsPaint)

        // Bronchial Tree branches (matching iOS WidgetVectorLungsBronchiShape)
        val bronchiPath = Path()
        bronchiPath.moveTo(w * 0.50f, h * 0.10f)
        bronchiPath.lineTo(w * 0.50f, h * 0.28f)

        // Left main bronchus & branches
        bronchiPath.moveTo(w * 0.50f, h * 0.28f)
        bronchiPath.quadTo(w * 0.42f, h * 0.34f, w * 0.33f, h * 0.46f)
        bronchiPath.quadTo(w * 0.30f, h * 0.56f, w * 0.27f, h * 0.66f)

        bronchiPath.moveTo(w * 0.33f, h * 0.46f)
        bronchiPath.quadTo(w * 0.37f, h * 0.53f, w * 0.38f, h * 0.62f)

        // Right main bronchus & branches
        bronchiPath.moveTo(w * 0.50f, h * 0.28f)
        bronchiPath.quadTo(w * 0.58f, h * 0.34f, w * 0.67f, h * 0.46f)
        bronchiPath.quadTo(w * 0.70f, h * 0.56f, w * 0.73f, h * 0.66f)

        bronchiPath.moveTo(w * 0.67f, h * 0.46f)
        bronchiPath.quadTo(w * 0.63f, h * 0.53f, w * 0.62f, h * 0.62f)

        val bronchiPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = max(1.5f, w * 0.025f)
            color = Color.argb(195, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawPath(bronchiPath, bronchiPaint)

        return bitmap
    }

    // =========================================================================
    // MARK: - Circular Rings & Gauges
    // =========================================================================

    fun createCircularProgressRingBitmap(
        sizePx: Int = 180,
        progress: Float,
        ringColorInt: Int,
        startColorInt: Int = ringColorInt,
        strokeWidthPx: Float = 16f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 3f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        // Track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(22, 255, 255, 255) // 8.5% white
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        // Arc
        val clamped = min(max(progress, 0.03f), 1.0f)
        val sweep = clamped * 360f
        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            strokeCap = Paint.Cap.ROUND
            if (startColorInt != ringColorInt) {
                shader = LinearGradient(
                    0f, 0f, sizePx.toFloat(), sizePx.toFloat(),
                    startColorInt, ringColorInt,
                    Shader.TileMode.CLAMP
                )
            } else {
                color = ringColorInt
            }
        }
        canvas.drawArc(oval, -90f, sweep, false, arcPaint)

        return bitmap
    }

    fun createMultiDrinkArcBitmap(
        sizePx: Int = 200,
        todayMl: Double,
        goalMl: Double,
        breakdown: List<Pair<Double, Int>> = emptyList(),
        strokeWidthPx: Float = 18f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(22, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        val safeGoal = max(goalMl, 1.0)
        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            strokeCap = Paint.Cap.ROUND
        }

        if (breakdown.isEmpty() || todayMl <= 0.0) {
            val progress = min(max((todayMl / safeGoal).toFloat(), 0.0f), 1.0f)
            if (progress > 0f) {
                arcPaint.shader = LinearGradient(
                    0f, 0f, sizePx.toFloat(), sizePx.toFloat(),
                    Color.parseColor("#00E5FF"), Color.parseColor("#00E676"),
                    Shader.TileMode.CLAMP
                )
                val sweep = max(progress * 360f, 10f)
                canvas.drawArc(oval, -90f, sweep, false, arcPaint)
            }
        } else {
            var runningAngle = -90f
            for ((amount, colorInt) in breakdown) {
                val sweep = (amount / safeGoal).toFloat() * 360f
                if (sweep > 0f) {
                    arcPaint.shader = null
                    arcPaint.color = colorInt
                    val clampedSweep = min(sweep, 360f - (runningAngle - (-90f)))
                    if (clampedSweep > 0f) {
                        canvas.drawArc(oval, runningAngle, clampedSweep, false, arcPaint)
                        runningAngle += clampedSweep
                    }
                }
                if (runningAngle >= 270f) break
            }
        }

        return bitmap
    }

    fun createSleepScoreRingBitmap(
        sizePx: Int = 200,
        score: Int,
        strokeWidthPx: Float = 18f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(22, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        val progress = min(max(score / 100f, 0f), 1f)
        if (progress > 0f) {
            val sweep = max(progress * 360f, 10f)
            val colors = intArrayOf(
                Color.parseColor("#00E5FF"),
                Color.parseColor("#3B82F6"),
                Color.parseColor("#8B5CF6"),
                Color.parseColor("#00E5FF")
            )
            val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx
                shader = SweepGradient(sizePx / 2f, sizePx / 2f, colors, null)
                strokeCap = Paint.Cap.ROUND
            }
            canvas.save()
            canvas.rotate(-90f, sizePx / 2f, sizePx / 2f)
            canvas.drawArc(oval, 0f, sweep, false, arcPaint)
            canvas.restore()
        }

        return bitmap
    }

    fun createSleepHypnogramBarBitmap(
        widthPx: Int = 400,
        heightPx: Int = 16,
        deepSec: Double,
        remSec: Double,
        lightSec: Double,
        awakeSec: Double
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val radius = heightPx / 2f

        val total = deepSec + remSec + lightSec + awakeSec
        if (total <= 0.0) {
            val emptyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(25, 255, 255, 255)
            }
            canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, emptyPaint)
            return bitmap
        }

        val clipPath = Path().apply {
            addRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, Path.Direction.CW)
        }
        canvas.clipPath(clipPath)

        var curX = 0f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // 1. Deep (Electric Indigo #6366F1)
        val deepW = (deepSec / total).toFloat() * widthPx
        if (deepW > 0f) {
            paint.color = Color.parseColor("#6366F1")
            canvas.drawRect(curX, 0f, curX + deepW, heightPx.toFloat(), paint)
            curX += deepW
        }

        // 2. REM (Vivid Purple #8B5CF6)
        val remW = (remSec / total).toFloat() * widthPx
        if (remW > 0f) {
            paint.color = Color.parseColor("#8B5CF6")
            canvas.drawRect(curX, 0f, curX + remW, heightPx.toFloat(), paint)
            curX += remW
        }

        // 3. Light (Electric Cyan #00E5FF)
        val lightW = (lightSec / total).toFloat() * widthPx
        if (lightW > 0f) {
            paint.color = Color.parseColor("#00E5FF")
            canvas.drawRect(curX, 0f, curX + lightW, heightPx.toFloat(), paint)
            curX += lightW
        }

        // 4. Awake (Accent Red #EF4444)
        val awakeW = (awakeSec / total).toFloat() * widthPx
        if (awakeW > 0f) {
            paint.color = Color.parseColor("#EF4444")
            canvas.drawRect(curX, 0f, widthPx.toFloat(), heightPx.toFloat(), paint)
        }

        return bitmap
    }

    fun createStressGaugeBitmap(
        sizePx: Int = 180,
        score: Int,
        levelColorInt: Int,
        strokeWidthPx: Float = 16f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(22, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        val progress = min(max(score / 100f, 0f), 1f)
        val sweep = max(progress * 360f, 10f)
        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = levelColorInt
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawArc(oval, -90f, sweep, false, arcPaint)

        return bitmap
    }

    fun createAutonomicBalanceBarBitmap(
        widthPx: Int = 300,
        heightPx: Int = 12,
        parasympatheticPct: Int = 60,
        sympatheticPct: Int = 40
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val radius = heightPx / 2f

        val clipPath = Path().apply {
            addRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, Path.Direction.CW)
        }
        canvas.clipPath(clipPath)

        val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#F97316")
            alpha = 110
        }
        canvas.drawRect(0f, 0f, widthPx.toFloat(), heightPx.toFloat(), activePaint)

        val restW = (parasympatheticPct.coerceIn(5, 95) / 100f) * widthPx
        val restPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, restW, 0f,
                Color.parseColor("#00E5FF"), Color.parseColor("#00FFB2"),
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, restW, heightPx.toFloat(), restPaint)

        return bitmap
    }

    fun createLinearProgressBarBitmap(
        widthPx: Int = 300,
        heightPx: Int = 10,
        progress: Float = 0.5f,
        activeColorInt: Int = Color.parseColor("#00E5FF"),
        trackColorInt: Int = Color.argb(31, 255, 255, 255)
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val radius = heightPx / 2f

        val clipPath = Path().apply {
            addRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, Path.Direction.CW)
        }
        canvas.clipPath(clipPath)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = trackColorInt
            style = Paint.Style.FILL
        }
        canvas.drawRect(0f, 0f, widthPx.toFloat(), heightPx.toFloat(), trackPaint)

        val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = activeColorInt
            style = Paint.Style.FILL
        }
        val fillW = (min(max(progress, 0.04f), 1f) * widthPx)
        canvas.drawRect(0f, 0f, fillW, heightPx.toFloat(), activePaint)

        return bitmap
    }

    fun createMiniMetricGaugeBitmap(
        sizePx: Int = 110,
        progress: Float,
        colorInt: Int,
        strokeWidthPx: Float = 10f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 2f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(22, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        val clamped = min(max(progress, 0.04f), 1f)
        val sweep = clamped * 360f
        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = colorInt
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawArc(oval, -90f, sweep, false, arcPaint)

        return bitmap
    }
}
