package com.intellidream.daily.designsystem

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs

/**
 * Calm Bounded Single-Step Swipeable Hub Navigation Modifier.
 * 1:1 behavioral port of iOS DragGesture in HealthMainView, HabitsMainView, FinancesMainView, and TagdosNotesHubView.
 *
 * Enforces:
 * 1. Edge Guard: Ignores swipes originating within [edgeGuardDp] from the screen edges (preserves system back).
 * 2. Horizontal Dominance: Requires horizontal delta to exceed vertical delta by at least [horizontalDominanceRatio]x.
 * 3. Distance Threshold: Requires at least [minDistanceDp] horizontal drag.
 * 4. Bounded Lock: Exactly ONE tab transition per continuous swipe.
 */
fun Modifier.calmBoundedSwipeGesture(
    currentIndex: Int,
    maxIndex: Int,
    edgeGuardDp: Dp = 60.dp,
    minDistanceDp: Dp = 50.dp,
    horizontalDominanceRatio: Float = 1.6f,
    onIndexChange: (Int) -> Unit
): Modifier = composed {
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    val edgeGuardPx = with(density) { edgeGuardDp.toPx() }
    val minDistancePx = with(density) { minDistanceDp.toPx() }

    pointerInput(currentIndex, maxIndex) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val startX = down.position.x

            // Edge guard: ignore if starting too close to screen edges
            if (startX < edgeGuardPx) {
                return@awaitEachGesture
            }

            var totalDx = 0f
            var totalDy = 0f
            var hasTriggered = false

            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull() ?: break

                if (change.pressed) {
                    val posChange = change.positionChange()
                    totalDx += posChange.x
                    totalDy += posChange.y

                    if (!hasTriggered && abs(totalDx) > minDistancePx) {
                        if (abs(totalDx) > abs(totalDy) * horizontalDominanceRatio) {
                            if (totalDx > 0 && currentIndex < maxIndex) {
                                hasTriggered = true
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onIndexChange(currentIndex + 1)
                            } else if (totalDx < 0 && currentIndex > 0) {
                                hasTriggered = true
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onIndexChange(currentIndex - 1)
                            }
                        }
                    }
                } else {
                    // Finger lifted
                    break
                }
            }
        }
    }
}
