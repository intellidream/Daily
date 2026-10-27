package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class WaterDayBucket(
    val dateStr: String,
    val dayLabel: String,
    val isToday: Boolean,
    val water: Double = 0.0,
    val coffee: Double = 0.0
) {
    val total: Double get() = water + coffee
}

@Serializable
data class SmokeDayBucket(
    val dateStr: String,
    val dayLabel: String,
    val isToday: Boolean,
    val cig: Double = 0.0,
    val heat: Double = 0.0
) {
    val total: Double get() = cig + heat
}
