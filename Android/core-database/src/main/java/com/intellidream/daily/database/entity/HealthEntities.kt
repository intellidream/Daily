package com.intellidream.daily.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.VitalMetricRecord

@Entity(
    tableName = "health_telemetry",
    indices = [
        Index(value = ["user_id", "type", "start_time"]),
        Index(value = ["start_time"]),
        Index(value = ["synced_at"])
    ]
)
data class HealthTelemetryEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String = "local_user",

    @ColumnInfo(name = "type")
    val type: String,

    @ColumnInfo(name = "value")
    val value: Double? = null,

    @ColumnInfo(name = "unit")
    val unit: String? = null,

    @ColumnInfo(name = "start_time")
    val startTime: Long,

    @ColumnInfo(name = "end_time")
    val endTime: Long? = null,

    @ColumnInfo(name = "source_device")
    val sourceDevice: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long? = System.currentTimeMillis(),

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null,

    @ColumnInfo(name = "external_id")
    val externalId: String? = null,

    @ColumnInfo(name = "source_id")
    val sourceId: String? = null,

    @ColumnInfo(name = "semantics")
    val semantics: String? = null,

    @ColumnInfo(name = "tz_offset_min")
    val tzOffsetMin: Int? = null,

    @ColumnInfo(name = "local_date")
    val localDate: String? = null,

    @ColumnInfo(name = "host_device_name")
    val hostDeviceName: String? = null,

    @ColumnInfo(name = "sensor_source_name")
    val sensorSourceName: String? = null,

    @ColumnInfo(name = "source_device_key")
    val sourceDeviceKey: String? = null,

    @ColumnInfo(name = "source_color")
    val sourceColor: String? = null
) {
    fun toRecord(): HealthTelemetryRecord = HealthTelemetryRecord(
        id = id,
        userId = userId,
        type = type,
        value = value,
        unit = unit,
        startTime = startTime,
        endTime = endTime,
        sourceDevice = sourceDevice,
        createdAt = createdAt,
        externalId = externalId,
        sourceId = sourceId,
        semantics = semantics,
        hostDeviceName = hostDeviceName,
        sensorSourceName = sensorSourceName,
        sourceDeviceKey = sourceDeviceKey,
        sourceColor = sourceColor,
        tzOffsetMin = tzOffsetMin,
        localDate = localDate
    )

    companion object {
        fun fromRecord(record: HealthTelemetryRecord, syncedAt: Long? = null): HealthTelemetryEntity =
            HealthTelemetryEntity(
                id = record.id,
                userId = record.userId,
                type = record.type,
                value = record.value,
                unit = record.unit,
                startTime = record.startTime,
                endTime = record.endTime,
                sourceDevice = record.sourceDevice,
                createdAt = record.createdAt ?: System.currentTimeMillis(),
                syncedAt = syncedAt,
                externalId = record.externalId,
                sourceId = record.sourceId,
                semantics = record.semantics,
                hostDeviceName = record.hostDeviceName,
                sensorSourceName = record.sensorSourceName,
                sourceDeviceKey = record.sourceDeviceKey,
                sourceColor = record.sourceColor,
                tzOffsetMin = record.tzOffsetMin,
                localDate = record.localDate
            )
    }
}

@Entity(
    tableName = "vitals",
    indices = [
        Index(value = ["user_id", "date"]),
        Index(value = ["date"]),
        Index(value = ["synced_at"])
    ]
)
data class VitalMetricEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String = "local_user",

    @ColumnInfo(name = "type")
    val type: String,

    @ColumnInfo(name = "value")
    val value: Double,

    @ColumnInfo(name = "unit")
    val unit: String? = null,

    @ColumnInfo(name = "date")
    val date: String,

    @ColumnInfo(name = "source_device")
    val sourceDevice: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long? = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long? = System.currentTimeMillis(),

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
) {
    fun toRecord(): VitalMetricRecord = VitalMetricRecord(
        id = id,
        userId = userId,
        type = type,
        value = value,
        unit = unit,
        date = date,
        sourceDevice = sourceDevice,
        createdAt = createdAt,
        updatedAt = updatedAt,
        syncedAt = syncedAt
    )

    companion object {
        fun fromRecord(record: VitalMetricRecord, syncedAt: Long? = null): VitalMetricEntity =
            VitalMetricEntity(
                id = record.id,
                userId = record.userId,
                type = record.type,
                value = record.value,
                unit = record.unit,
                date = record.date,
                sourceDevice = record.sourceDevice,
                createdAt = record.createdAt ?: System.currentTimeMillis(),
                updatedAt = record.updatedAt ?: System.currentTimeMillis(),
                syncedAt = syncedAt
            )
    }
}

@Entity(
    tableName = "health_daily_summary_cache",
    indices = [
        Index(value = ["user_id", "date_key"], unique = true),
        Index(value = ["date_key"])
    ]
)
data class HealthDailySummaryEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String,

    @ColumnInfo(name = "date_key")
    val dateKey: String, // "yyyy-MM-dd"

    @ColumnInfo(name = "summary_version")
    val summaryVersion: Int = 1,

    @ColumnInfo(name = "payload_json")
    val payloadJson: String,

    @ColumnInfo(name = "computed_at")
    val computedAt: Long? = null,

    @ColumnInfo(name = "cached_at")
    val cachedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "source_device_primary")
    val sourceDevicePrimary: String? = null
)

