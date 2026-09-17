package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.VitalMetricEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HealthTelemetryDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecords(records: List<HealthTelemetryEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecord(record: HealthTelemetryEntity)

    @Query("SELECT * FROM health_telemetry WHERE user_id = :userId AND start_time >= :startTime AND start_time <= :endTime ORDER BY start_time ASC")
    fun getTelemetryBetween(userId: String, startTime: Long, endTime: Long): Flow<List<HealthTelemetryEntity>>

    @Query("SELECT * FROM health_telemetry WHERE user_id = :userId AND start_time >= :startTime AND start_time <= :endTime ORDER BY start_time ASC")
    suspend fun getTelemetryBetweenSync(userId: String, startTime: Long, endTime: Long): List<HealthTelemetryEntity>

    @Query("SELECT * FROM health_telemetry WHERE synced_at IS NULL ORDER BY start_time ASC LIMIT 500")
    suspend fun getUnsyncedRecords(): List<HealthTelemetryEntity>

    @Query("UPDATE health_telemetry SET synced_at = :syncedAt WHERE id IN (:ids)")
    suspend fun markRecordsSynced(ids: List<String>, syncedAt: Long)

    @Query("DELETE FROM health_telemetry WHERE start_time < :cutoffTime")
    suspend fun deleteTelemetryBefore(cutoffTime: Long)
}

@Dao
interface VitalMetricDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertVitals(vitals: List<VitalMetricEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertVital(vital: VitalMetricEntity)

    @Query("SELECT * FROM vitals WHERE user_id = :userId AND date = :date")
    fun getVitalsForDate(userId: String, date: String): Flow<List<VitalMetricEntity>>

    @Query("SELECT * FROM vitals WHERE user_id = :userId AND date = :date")
    suspend fun getVitalsForDateSync(userId: String, date: String): List<VitalMetricEntity>

    @Query("SELECT * FROM vitals WHERE user_id = :userId AND date >= :startDate AND date <= :endDate ORDER BY date ASC")
    fun getVitalsBetweenDates(userId: String, startDate: String, endDate: String): Flow<List<VitalMetricEntity>>

    @Query("SELECT * FROM vitals WHERE user_id = :userId AND date >= :startDate AND date <= :endDate ORDER BY date ASC")
    suspend fun getVitalsBetweenDatesSync(userId: String, startDate: String, endDate: String): List<VitalMetricEntity>

    @Query("SELECT * FROM vitals WHERE synced_at IS NULL ORDER BY updated_at ASC LIMIT 100")
    suspend fun getUnsyncedVitals(): List<VitalMetricEntity>

    @Query("UPDATE vitals SET synced_at = :syncedAt WHERE id IN (:ids)")
    suspend fun markVitalsSynced(ids: List<String>, syncedAt: Long)
}
