package com.intellidream.daily.database.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "prism_clips")
data class PrismClipEntity(
    @PrimaryKey val id: String,
    val userId: String?,
    val clipType: String,
    val title: String,
    val sourceUrl: String,
    val domain: String,
    val contentText: String,
    val userNote: String,
    val tagsCsv: String,
    val previewImageUrl: String?,
    val storagePath: String?,
    val imageWidth: Int?,
    val imageHeight: Int?,
    val isFavorite: Boolean,
    val isDeleted: Boolean,
    val tagdosNoteId: String?,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val isDirty: Boolean = false
)

@Entity(tableName = "prism_pinned_sites")
data class PrismPinnedSiteEntity(
    @PrimaryKey val id: String,
    val userId: String?,
    val title: String,
    val url: String,
    val domain: String,
    val iconUrl: String?,
    val displayOrder: Int,
    val isDeleted: Boolean,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val isDirty: Boolean = false
)
