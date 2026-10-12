package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class HabitGoal(
    val habit_type: String? = null,
    val target_value: Double? = null
)

@Serializable
data class UserPreference(
    val smokes_baseline: Int? = null
)

@Serializable
data class DeleteUpdate(
    val is_deleted: Boolean = true
)
