package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class WatchPairingInsert(
    val pin_code: String
)

@Serializable
data class WatchPairing(
    val pin_code: String,
    val user_id: String? = null,
    val access_token: String? = null,
    val refresh_token: String? = null,
    val created_at: String? = null,
    val expires_at: String? = null,
    val claimed: Boolean? = null
)
