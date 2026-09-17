package com.intellidream.daily.model

import kotlinx.serialization.Serializable

@Serializable
enum class AuthProvider(val value: String, val displayName: String) {
    Google("google", "Google"),
    Apple("apple", "Apple"),
    Email("email", "Email"),
    Guest("guest", "Guest")
}

@Serializable
data class UserProfile(
    val id: String,
    val email: String? = null,
    val fullName: String? = null,
    val avatarUrl: String? = null,
    val provider: AuthProvider = AuthProvider.Guest,
    val createdAt: Long? = null
) {
    /**
     * Derives user's first name using the exact heuristic from WinUI & iOS:
     * 1. Splits fullName by spaces, picks first segment.
     * 2. If absent, parses email local part (splitting on '.', '_', '-') and capitalizes leading token.
     * 3. Fallback: "User" (or "Friend" if guest).
     */
    val firstName: String
        get() {
            val trimmedName = fullName?.trim()
            if (!trimmedName.isNullOrEmpty()) {
                val first = trimmedName.split(" ").firstOrNull { it.isNotEmpty() }
                if (!first.isNullOrEmpty()) return first
            }

            if (!email.isNullOrEmpty()) {
                val localPart = email.substringBefore("@")
                val namePart = localPart.split('.', '_', '-').firstOrNull { it.isNotEmpty() }
                if (!namePart.isNullOrEmpty()) {
                    return namePart.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
                }
            }

            return if (provider == AuthProvider.Guest) "Friend" else "User"
        }

    companion object {
        val guest = UserProfile(
            id = "guest_local",
            email = null,
            fullName = "Guest User",
            avatarUrl = null,
            provider = AuthProvider.Guest,
            createdAt = System.currentTimeMillis()
        )
    }
}

sealed interface AuthSessionState {
    data object Initializing : AuthSessionState
    data object Unauthenticated : AuthSessionState
    data class Authenticated(override val profile: UserProfile) : AuthSessionState
    data object Guest : AuthSessionState

    val isAuthenticatedOrGuest: Boolean
        get() = this is Authenticated || this is Guest

    val profile: UserProfile?
        get() = when (this) {
            is Authenticated -> profile
            is Guest -> UserProfile.guest
            else -> null
        }
}
