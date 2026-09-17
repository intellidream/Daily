package com.intellidream.daily.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "smart_ledgers")
data class SmartLedgerEntity(
    @PrimaryKey
    val id: String = "primary_ledger",
    @ColumnInfo(name = "raw_text")
    val rawText: String,
    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
)
