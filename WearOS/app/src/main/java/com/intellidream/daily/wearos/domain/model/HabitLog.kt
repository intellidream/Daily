package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HabitLog(
    val id: String = UUID.randomUUID().toString(),
    val user_id: String? = null,
    val habit_type: String,
    val value: Double,
    val unit: String,
    val logged_at: String,
    val metadata: String? = null,
    val is_deleted: Boolean = false
)
