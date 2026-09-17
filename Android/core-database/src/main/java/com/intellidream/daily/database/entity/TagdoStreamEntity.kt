package com.intellidream.daily.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entity representing a TagDoS stream row.
 * Matches iOS Supabase schema for `tagdos_streams`.
 */
@Entity(tableName = "tagdos_streams")
data class TagdoStreamEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "order_index")
    val orderIndex: Int,

    @ColumnInfo(name = "title")
    val title: String,

    @ColumnInfo(name = "custom_title")
    val customTitle: String? = null,

    @ColumnInfo(name = "raw_text")
    val rawText: String,

    @ColumnInfo(name = "stream_reminder")
    val streamReminder: Long? = null,

    @ColumnInfo(name = "active_memos")
    val activeMemos: String = "",

    @ColumnInfo(name = "attachments_json")
    val attachmentsJson: String = "[]",

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
)
