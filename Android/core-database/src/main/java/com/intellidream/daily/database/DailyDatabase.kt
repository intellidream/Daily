package com.intellidream.daily.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.intellidream.daily.database.dao.HabitLogDao
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.HabitLogEntity
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.VitalMetricEntity

@Database(
    entities = [
        HabitLogEntity::class,
        HealthTelemetryEntity::class,
        VitalMetricEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class DailyDatabase : RoomDatabase() {

    abstract fun habitLogDao(): HabitLogDao
    abstract fun healthTelemetryDao(): HealthTelemetryDao
    abstract fun vitalMetricDao(): VitalMetricDao

    companion object {
        @Volatile
        private var INSTANCE: DailyDatabase? = null

        fun getDatabase(context: Context): DailyDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    DailyDatabase::class.java,
                    "DailyAndroid.db"
                )
                    .fallbackToDestructiveMigration(dropAllTables = true)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
