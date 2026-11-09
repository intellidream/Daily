package com.intellidream.daily.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.intellidream.daily.database.dao.HabitLogDao
import com.intellidream.daily.database.dao.HealthDailySummaryDao
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.NewsDao
import com.intellidream.daily.database.dao.PrismDao
import com.intellidream.daily.database.dao.SmartLedgerDao
import com.intellidream.daily.database.dao.TagdosDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.CachedFeedArticleEntity
import com.intellidream.daily.database.entity.HabitLogEntity
import com.intellidream.daily.database.entity.HealthDailySummaryEntity
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.PrismClipEntity
import com.intellidream.daily.database.entity.PrismPinnedSiteEntity
import com.intellidream.daily.database.entity.RssSubscriptionEntity
import com.intellidream.daily.database.entity.SavedArticleEntity
import com.intellidream.daily.database.entity.SmartLedgerEntity
import com.intellidream.daily.database.entity.TagdoQuickNoteEntity
import com.intellidream.daily.database.entity.TagdoStreamEntity
import com.intellidream.daily.database.entity.VitalMetricEntity

@Database(
    entities = [
        HabitLogEntity::class,
        HealthTelemetryEntity::class,
        VitalMetricEntity::class,
        HealthDailySummaryEntity::class,
        SmartLedgerEntity::class,
        TagdoStreamEntity::class,
        TagdoQuickNoteEntity::class,
        RssSubscriptionEntity::class,
        SavedArticleEntity::class,
        CachedFeedArticleEntity::class,
        PrismClipEntity::class,
        PrismPinnedSiteEntity::class
    ],
    version = 10,
    exportSchema = false
)
abstract class DailyDatabase : RoomDatabase() {

    abstract fun habitLogDao(): HabitLogDao
    abstract fun healthTelemetryDao(): HealthTelemetryDao
    abstract fun vitalMetricDao(): VitalMetricDao
    abstract fun healthDailySummaryDao(): HealthDailySummaryDao
    abstract fun smartLedgerDao(): SmartLedgerDao
    abstract fun tagdosDao(): TagdosDao
    abstract fun newsDao(): NewsDao
    abstract fun prismDao(): PrismDao

    companion object {
        @Volatile
        private var INSTANCE: DailyDatabase? = null

        val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `prism_clips` (
                        `id` TEXT NOT NULL,
                        `userId` TEXT,
                        `clipType` TEXT NOT NULL,
                        `title` TEXT NOT NULL,
                        `sourceUrl` TEXT NOT NULL,
                        `domain` TEXT NOT NULL,
                        `contentText` TEXT NOT NULL,
                        `userNote` TEXT NOT NULL,
                        `tagsCsv` TEXT NOT NULL,
                        `previewImageUrl` TEXT,
                        `storagePath` TEXT,
                        `imageWidth` INTEGER,
                        `imageHeight` INTEGER,
                        `isFavorite` INTEGER NOT NULL,
                        `isDeleted` INTEGER NOT NULL,
                        `tagdosNoteId` TEXT,
                        `createdAtMs` INTEGER NOT NULL,
                        `updatedAtMs` INTEGER NOT NULL,
                        `isDirty` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `prism_pinned_sites` (
                        `id` TEXT NOT NULL,
                        `userId` TEXT,
                        `title` TEXT NOT NULL,
                        `url` TEXT NOT NULL,
                        `domain` TEXT NOT NULL,
                        `iconUrl` TEXT,
                        `displayOrder` INTEGER NOT NULL,
                        `isDeleted` INTEGER NOT NULL,
                        `createdAtMs` INTEGER NOT NULL,
                        `updatedAtMs` INTEGER NOT NULL,
                        `isDirty` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
            }
        }

        fun getDatabase(context: Context): DailyDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    DailyDatabase::class.java,
                    "DailyAndroid.db"
                )
                    .addMigrations(MIGRATION_9_10)
                    .fallbackToDestructiveMigration(dropAllTables = true)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
