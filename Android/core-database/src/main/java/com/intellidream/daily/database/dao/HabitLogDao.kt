package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.intellidream.daily.database.entity.HabitLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HabitLogDao {

    @Query("""
        SELECT * FROM habits_logs 
        WHERE habit_type = :habitType AND is_deleted = 0 
          AND logged_at >= :startOfDay AND logged_at <= :endOfDay 
        ORDER BY logged_at DESC
    """)
    fun getLogsForDate(habitType: String, startOfDay: Long, endOfDay: Long): Flow<List<HabitLogEntity>>

    @Query("""
        SELECT * FROM habits_logs 
        WHERE habit_type = :habitType AND is_deleted = 0 
          AND logged_at >= :start AND logged_at <= :end 
        ORDER BY logged_at ASC
    """)
    fun getLogsBetween(habitType: String, start: Long, end: Long): Flow<List<HabitLogEntity>>

    @Query("""
        SELECT * FROM habits_logs 
        WHERE habit_type = :habitType AND is_deleted = 0 
        ORDER BY logged_at DESC
    """)
    fun getAllActiveLogs(habitType: String): Flow<List<HabitLogEntity>>

    @Query("SELECT * FROM habits_logs WHERE synced_at IS NULL AND is_deleted = 0")
    suspend fun getUnsyncedLogs(): List<HabitLogEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: HabitLogEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(entities: List<HabitLogEntity>)

    @Update
    suspend fun update(entity: HabitLogEntity)

    @Query("UPDATE habits_logs SET synced_at = :timestamp WHERE id = :id")
    suspend fun markSynced(id: String, timestamp: Long)

    @Query("UPDATE habits_logs SET is_deleted = 1, updated_at = :timestamp, synced_at = NULL WHERE id = :id")
    suspend fun softDelete(id: String, timestamp: Long = System.currentTimeMillis())

    @Query("DELETE FROM habits_logs WHERE id = :id")
    suspend fun hardDelete(id: String)

    @Query("DELETE FROM habits_logs")
    suspend fun clearAll()
}
