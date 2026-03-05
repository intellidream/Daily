package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class HabitGoal(
    val target_value: Double?
)

@Serializable
data class UserPreference(
    val smokes_baseline: Int?
)

@Serializable
data class DeleteUpdate(
    val is_deleted: Boolean = true
)
