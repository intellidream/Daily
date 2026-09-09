package com.intellidream.daily.wearos.domain.model

data class WaterDayBucket(
    val dateStr: String,
    val dayLabel: String,
    val isToday: Boolean,
    var water: Double = 0.0,
    var coffee: Double = 0.0
) {
    val total: Double get() = water + coffee
}

data class SmokeDayBucket(
    val dateStr: String,
    val dayLabel: String,
    val isToday: Boolean,
    var cig: Double = 0.0,
    var heat: Double = 0.0
) {
    val total: Double get() = cig + heat
}
