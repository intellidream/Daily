package com.intellidream.daily.presentation

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.ContextWrapper
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

object BiometricAuthHelper {

    fun getActivity(context: Context): Activity? {
        var current = context
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
    }

    fun isBiometricAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bm = context.getSystemService(Context.BIOMETRIC_SERVICE) as? BiometricManager
            if (bm != null) {
                val res = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    bm.canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                } else {
                    bm.canAuthenticate()
                }
                return res == BiometricManager.BIOMETRIC_SUCCESS
            }
        }
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return km?.isDeviceSecure == true
    }

    fun prompt(
        activity: Activity,
        title: String = "Supabase Admin Console",
        subtitle: String = "Confirm identity to access cloud telemetry",
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signal = CancellationSignal()
            val builder = BiometricPrompt.Builder(activity)
                .setTitle(title)
                .setSubtitle(subtitle)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                builder.setNegativeButton("Cancel", activity.mainExecutor) { _, _ ->
                    onError("Cancelled")
                }
            }

            val prompt = builder.build()
            prompt.authenticate(
                signal,
                activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                        super.onAuthenticationSucceeded(result)
                        onSuccess()
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                        super.onAuthenticationError(errorCode, errString)
                        onError(errString?.toString() ?: "Authentication error ($errorCode)")
                    }
                }
            )
        } else {
            val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (km != null && km.isDeviceSecure) {
                val intent = km.createConfirmDeviceCredentialIntent(title, subtitle)
                if (intent != null) {
                    activity.startActivity(intent)
                    onSuccess()
                    return
                }
            }
            onSuccess()
        }
    }
}
