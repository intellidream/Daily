package com.intellidream.daily.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.intellidream.daily.model.HabitLogRecord

@Entity(
    tableName = "habits_logs",
    indices = [
        Index(value = ["habit_type", "logged_at"]),
        Index(value = ["synced_at"])
    ]
)
data class HabitLogEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String? = null,

    @ColumnInfo(name = "habit_type")
    val habitType: String,

    @ColumnInfo(name = "value")
    val value: Double,

    @ColumnInfo(name = "unit")
    val unit: String,

    @ColumnInfo(name = "logged_at")
    val loggedAt: Long,

    @ColumnInfo(name = "metadata")
    val metadata: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
) {
    fun toRecord(): HabitLogRecord = HabitLogRecord(
        id = id,
        userId = userId,
        habitType = habitType,
        value = value,
        unit = unit,
        loggedAt = loggedAt,
        metadata = metadata,
        createdAt = createdAt,
        updatedAt = updatedAt,
        isDeleted = isDeleted
    )

    companion object {
        fun fromRecord(record: HabitLogRecord, syncedAt: Long? = null): HabitLogEntity = HabitLogEntity(
            id = record.id,
            userId = record.userId,
            habitType = record.habitType,
            value = record.value,
            unit = record.unit,
            loggedAt = record.loggedAt,
            metadata = record.metadata,
            createdAt = record.createdAt,
            updatedAt = record.updatedAt,
            isDeleted = record.isDeleted,
            syncedAt = syncedAt
        )
    }
}
