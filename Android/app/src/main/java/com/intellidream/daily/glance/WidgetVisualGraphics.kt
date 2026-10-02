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

/**
 * High-performance, anti-aliased Canvas drawer that produces crisp, high-DPI bitmaps
 * for Jetpack Glance AppWidgets, matching iOS WidgetKit 1:1 visual fidelity.
 */
object WidgetVisualGraphics {

    // MARK: - Multi-Drink Stratified Arc Ring (Bubbles)
    fun createMultiDrinkArcBitmap(
        sizePx: Int = 200,
        todayMl: Double,
        goalMl: Double,
        breakdown: List<Pair<Double, Int>> = emptyList(), // amount to ColorInt
        strokeWidthPx: Float = 18f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        // 1. Subtle background track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(25, 255, 255, 255) // 10% white
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

    // MARK: - Anatomical Vector Lungs & Progress Ring (Smokes)
    fun createSmokesGaugeBitmap(
        sizePx: Int = 200,
        todayTotal: Int,
        baseline: Int,
        ringColorInt: Int,
        lungColorInt: Int,
        strokeWidthPx: Float = 18f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        // 1. Background Track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(25, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        // 2. Foreground Health Progress Arc
        val safeBase = max(baseline, 1).toFloat()
        val progress = min(max(todayTotal.toFloat() / safeBase, 0.0f), 1.0f)
        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = ringColorInt
            strokeCap = Paint.Cap.ROUND
        }
        val sweep = max(progress * 360f, 12f)
        canvas.drawArc(oval, -90f, sweep, false, arcPaint)

        // 3. Anatomical Vector Lungs Shape in Center
        val lungWidth = sizePx * 0.44f
        val lungHeight = sizePx * 0.44f
        val left = (sizePx - lungWidth) / 2f
        val top = (sizePx - lungHeight) / 2f - (sizePx * 0.04f)

        val lungsPath = Path()
        // Trachea / Airway
        lungsPath.moveTo(left + lungWidth * 0.47f, top + lungHeight * 0.05f)
        lungsPath.lineTo(left + lungWidth * 0.53f, top + lungHeight * 0.05f)
        lungsPath.lineTo(left + lungWidth * 0.53f, top + lungHeight * 0.28f)
        lungsPath.lineTo(left + lungWidth * 0.47f, top + lungHeight * 0.28f)
        lungsPath.close()

        // Left Lung Lobe
        lungsPath.moveTo(left + lungWidth * 0.46f, top + lungHeight * 0.29f)
        lungsPath.cubicTo(
            left + lungWidth * 0.30f, top + lungHeight * 0.26f,
            left + lungWidth * 0.12f, top + lungHeight * 0.38f,
            left + lungWidth * 0.12f, top + lungHeight * 0.52f
        )
        lungsPath.cubicTo(
            left + lungWidth * 0.12f, top + lungHeight * 0.72f,
            left + lungWidth * 0.22f, top + lungHeight * 0.88f,
            left + lungWidth * 0.38f, top + lungHeight * 0.90f
        )
        lungsPath.cubicTo(
            left + lungWidth * 0.42f, top + lungHeight * 0.80f,
            left + lungWidth * 0.44f, top + lungHeight * 0.52f,
            left + lungWidth * 0.46f, top + lungHeight * 0.38f
        )
        lungsPath.close()

        // Right Lung Lobe
        lungsPath.moveTo(left + lungWidth * 0.54f, top + lungHeight * 0.29f)
        lungsPath.cubicTo(
            left + lungWidth * 0.70f, top + lungHeight * 0.26f,
            left + lungWidth * 0.88f, top + lungHeight * 0.38f,
            left + lungWidth * 0.88f, top + lungHeight * 0.52f
        )
        lungsPath.cubicTo(
            left + lungWidth * 0.88f, top + lungHeight * 0.72f,
            left + lungWidth * 0.78f, top + lungHeight * 0.88f,
            left + lungWidth * 0.62f, top + lungHeight * 0.90f
        )
        lungsPath.cubicTo(
            left + lungWidth * 0.58f, top + lungHeight * 0.80f,
            left + lungWidth * 0.56f, top + lungHeight * 0.52f,
            left + lungWidth * 0.54f, top + lungHeight * 0.38f
        )
        lungsPath.close()

        val lungsPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = lungColorInt
            alpha = 210
        }
        canvas.drawPath(lungsPath, lungsPaint)

        // Bronchi branches (fine white lines)
        val bronchiPath = Path()
        bronchiPath.moveTo(left + lungWidth * 0.50f, top + lungHeight * 0.12f)
        bronchiPath.lineTo(left + lungWidth * 0.50f, top + lungHeight * 0.28f)

        // Left branch
        bronchiPath.moveTo(left + lungWidth * 0.50f, top + lungHeight * 0.28f)
        bronchiPath.quadTo(
            left + lungWidth * 0.42f, top + lungHeight * 0.34f,
            left + lungWidth * 0.33f, top + lungHeight * 0.46f
        )
        bronchiPath.quadTo(
            left + lungWidth * 0.30f, top + lungHeight * 0.56f,
            left + lungWidth * 0.27f, top + lungHeight * 0.66f
        )

        // Right branch
        bronchiPath.moveTo(left + lungWidth * 0.50f, top + lungHeight * 0.28f)
        bronchiPath.quadTo(
            left + lungWidth * 0.58f, top + lungHeight * 0.34f,
            left + lungWidth * 0.67f, top + lungHeight * 0.46f
        )
        bronchiPath.quadTo(
            left + lungWidth * 0.70f, top + lungHeight * 0.56f,
            left + lungWidth * 0.73f, top + lungHeight * 0.66f
        )

        val bronchiPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2.5f
            color = Color.argb(190, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawPath(bronchiPath, bronchiPaint)

        return bitmap
    }

    // MARK: - Sleep Score Angular Gradient Ring (Sleep Studio)
    fun createSleepScoreRingBitmap(
        sizePx: Int = 200,
        score: Int,
        strokeWidthPx: Float = 18f
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = strokeWidthPx / 2f + 4f
        val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

        // 1. Background Track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(25, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        // 2. Gradient Arc (Cyan -> Blue -> Purple)
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

    // MARK: - Multi-Stage Proportional Sleep Architecture Bar
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
                color = Color.argb(35, 255, 255, 255)
            }
            canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, emptyPaint)
            return bitmap
        }

        // Draw clipped pill
        val clipPath = Path().apply {
            addRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, Path.Direction.CW)
        }
        canvas.clipPath(clipPath)

        var curX = 0f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // 1. Deep (Electric Indigo)
        val deepW = (deepSec / total).toFloat() * widthPx
        if (deepW > 0f) {
            paint.color = Color.parseColor("#6366F1")
            canvas.drawRect(curX, 0f, curX + deepW, heightPx.toFloat(), paint)
            curX += deepW
        }

        // 2. REM (Vivid Purple)
        val remW = (remSec / total).toFloat() * widthPx
        if (remW > 0f) {
            paint.color = Color.parseColor("#A855F7")
            canvas.drawRect(curX, 0f, curX + remW, heightPx.toFloat(), paint)
            curX += remW
        }

        // 3. Light (Electric Cyan)
        val lightW = (lightSec / total).toFloat() * widthPx
        if (lightW > 0f) {
            paint.color = Color.parseColor("#00E5FF")
            canvas.drawRect(curX, 0f, curX + lightW, heightPx.toFloat(), paint)
            curX += lightW
        }

        // 4. Awake (Amber Gold)
        val awakeW = (awakeSec / total).toFloat() * widthPx
        if (awakeW > 0f) {
            paint.color = Color.parseColor("#FFB800")
            canvas.drawRect(curX, 0f, widthPx.toFloat(), heightPx.toFloat(), paint)
        }

        return bitmap
    }

    // MARK: - Circular Stress Score Gauge
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

        // Background Track
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            color = Color.argb(25, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        // Stress Progress Arc
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

    // MARK: - Autonomic Nervous System Balance Bar (Rest vs Active)
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

        // Background / Active sympathetic orange
        val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#F97316")
            alpha = 130
        }
        canvas.drawRect(0f, 0f, widthPx.toFloat(), heightPx.toFloat(), activePaint)

        // Rest parasympathetic cyan/mint gradient
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

    // MARK: - Circular Mini Metric Gauge (for Combined Widget)
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
            color = Color.argb(25, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawOval(oval, trackPaint)

        val clamped = min(max(progress, 0.05f), 1f)
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
