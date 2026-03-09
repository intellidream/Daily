package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class PairedWatch(
    val id: String? = null,
    val user_id: String? = null,
    val platform: String? = null,
    val device_name: String? = null,
    val paired_at: String? = null,
    val last_token_push: String? = null,
    val pending_access_token: String? = null,
    val pending_refresh_token: String? = null,
    val is_active: Boolean? = null
)
