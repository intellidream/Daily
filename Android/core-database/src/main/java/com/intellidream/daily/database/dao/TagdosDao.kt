package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.intellidream.daily.database.entity.TagdoQuickNoteEntity
import com.intellidream.daily.database.entity.TagdoStreamEntity
import kotlinx.coroutines.flow.Flow

/**
 * Room Data Access Object for TagDoS streams and quick notes.
 */
@Dao
interface TagdosDao {

    // MARK: - Streams

    @Query("SELECT * FROM tagdos_streams ORDER BY order_index ASC")
    fun getAllStreamsFlow(): Flow<List<TagdoStreamEntity>>

    @Query("SELECT * FROM tagdos_streams WHERE id = :id")
    suspend fun getStreamById(id: String): TagdoStreamEntity?

    @Upsert
    suspend fun upsertStream(entity: TagdoStreamEntity)

    @Upsert
    suspend fun upsertStreams(entities: List<TagdoStreamEntity>)

    @Query("DELETE FROM tagdos_streams WHERE id = :id")
    suspend fun deleteStreamById(id: String)

    @Query("SELECT * FROM tagdos_streams WHERE synced_at IS NULL")
    suspend fun getUnsyncedStreams(): List<TagdoStreamEntity>

    // MARK: - Quick Notes

    @Query("SELECT * FROM tagdos_quick_notes ORDER BY is_pinned DESC, updated_at DESC")
    fun getAllNotesFlow(): Flow<List<TagdoQuickNoteEntity>>

    @Query("SELECT * FROM tagdos_quick_notes WHERE id = :id")
    suspend fun getNoteById(id: String): TagdoQuickNoteEntity?

    @Upsert
    suspend fun upsertNote(entity: TagdoQuickNoteEntity)

    @Upsert
    suspend fun upsertNotes(entities: List<TagdoQuickNoteEntity>)

    @Query("DELETE FROM tagdos_quick_notes WHERE id = :id")
    suspend fun deleteNoteById(id: String)

    @Query("SELECT * FROM tagdos_quick_notes WHERE synced_at IS NULL")
    suspend fun getUnsyncedNotes(): List<TagdoQuickNoteEntity>
}
