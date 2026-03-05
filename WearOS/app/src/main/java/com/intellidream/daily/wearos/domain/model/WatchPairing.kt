package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class WatchPairing(
    val code: String,
    val access_token: String? = null,
    val refresh_token: String? = null,
    val created_at: String? = null
)
