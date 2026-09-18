package com.intellidream.daily.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.intellidream.daily.database.dao.HabitLogDao
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.SmartLedgerDao
import com.intellidream.daily.database.dao.TagdosDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.HabitLogEntity
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.SmartLedgerEntity
import com.intellidream.daily.database.dao.NewsDao
import com.intellidream.daily.database.entity.RssSubscriptionEntity
import com.intellidream.daily.database.entity.SavedArticleEntity
import com.intellidream.daily.database.entity.TagdoQuickNoteEntity
import com.intellidream.daily.database.entity.TagdoStreamEntity
import com.intellidream.daily.database.entity.VitalMetricEntity

@Database(
    entities = [
        HabitLogEntity::class,
        HealthTelemetryEntity::class,
        VitalMetricEntity::class,
        SmartLedgerEntity::class,
        TagdoStreamEntity::class,
        TagdoQuickNoteEntity::class,
        RssSubscriptionEntity::class,
        SavedArticleEntity::class
    ],
    version = 5,
    exportSchema = false
)
abstract class DailyDatabase : RoomDatabase() {

    abstract fun habitLogDao(): HabitLogDao
    abstract fun healthTelemetryDao(): HealthTelemetryDao
    abstract fun vitalMetricDao(): VitalMetricDao
    abstract fun smartLedgerDao(): SmartLedgerDao
    abstract fun tagdosDao(): TagdosDao
    abstract fun newsDao(): NewsDao

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
