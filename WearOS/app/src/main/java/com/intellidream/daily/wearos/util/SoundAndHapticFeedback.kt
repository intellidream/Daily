package com.intellidream.daily.wearos.util

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Provides gentle, subtle sound and tactile haptic feedback on WearOS,
 * matching watchOS haptic & sound behavior (.success and .click).
 */
object SoundAndHapticFeedback {

    private var toneGenerator: ToneGenerator? = null

    init {
        try {
            // STREAM_NOTIFICATION with gentle volume (35/100)
            toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 35)
        } catch (_: Exception) {
            try {
                toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 35)
            } catch (_: Exception) {}
        }
    }

    /**
     * Plays a pleasant success feedback:
     * - A subtle ascending double-pulse vibration (watchOS-like)
     * - A soft, crisp chime (if device is not in silent / do-not-disturb mode)
     */
    fun playSuccess(context: Context, view: View? = null) {
        // 1. Tactile feedback
        vibrateSuccess(context, view)

        // 2. Subtle audio chime
        playTone(context, ToneGenerator.TONE_PROP_BEEP2, durationMs = 45)
    }

    /**
     * Feedback when a new habit log is added:
     * Plays a crisp, satisfying success feedback.
     */
    fun playLogAdded(context: Context, view: View? = null) {
        playSuccess(context, view)
    }

    /**
     * Feedback for button taps, temporal navigation, and log clicks:
     * - Single subtle tick / click haptic
     */
    fun playClick(context: Context, view: View? = null) {
        view?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)

        try {
            val vibrator = getVibrator(context)
            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
                } else {
                    vibrator.vibrate(VibrationEffect.createOneShot(25, VibrationEffect.DEFAULT_AMPLITUDE))
                }
            }
        } catch (_: Exception) {}
    }

    private fun vibrateSuccess(context: Context, view: View? = null) {
        view?.performHapticFeedback(HapticFeedbackConstants.CONFIRM)

        try {
            val vibrator = getVibrator(context)
            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Ascending delicate double-pulse: wait 0ms, buzz 25ms, pause 45ms, buzz 30ms
                    val timings = longArrayOf(0, 25, 45, 30)
                    val amplitudes = intArrayOf(0, 160, 0, 220)
                    val effect = VibrationEffect.createWaveform(timings, amplitudes, -1)
                    vibrator.vibrate(effect)
                } else {
                    vibrator.vibrate(VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE))
                }
            }
        } catch (_: Exception) {}
    }

    private fun playTone(context: Context, toneType: Int, durationMs: Int) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            // Respect silent / vibrate / DND mode
            if (audioManager?.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                return
            }
            toneGenerator?.startTone(toneType, durationMs)
        } catch (_: Exception) {}
    }

    private fun getVibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }
}
