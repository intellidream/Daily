package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.intellidream.daily.database.entity.PrismClipEntity
import com.intellidream.daily.database.entity.PrismPinnedSiteEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PrismDao {

    @Query("SELECT * FROM prism_clips WHERE isDeleted = 0 ORDER BY isFavorite DESC, createdAtMs DESC")
    fun observeActiveClips(): Flow<List<PrismClipEntity>>

    @Query("SELECT * FROM prism_clips WHERE id = :id LIMIT 1")
    suspend fun getClipById(id: String): PrismClipEntity?

    @Query("SELECT * FROM prism_clips WHERE isDirty = 1")
    suspend fun getDirtyClips(): List<PrismClipEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertClip(entity: PrismClipEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertClips(entities: List<PrismClipEntity>)

    @Query("SELECT * FROM prism_pinned_sites WHERE isDeleted = 0 ORDER BY displayOrder ASC")
    fun observeActivePinnedSites(): Flow<List<PrismPinnedSiteEntity>>

    @Query("SELECT * FROM prism_pinned_sites")
    suspend fun getAllPinnedSites(): List<PrismPinnedSiteEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertPinnedSite(entity: PrismPinnedSiteEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertPinnedSites(entities: List<PrismPinnedSiteEntity>)
}
