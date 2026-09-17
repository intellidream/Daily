package com.intellidream.daily.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.intellidream.daily.database.dao.HabitLogDao
import com.intellidream.daily.database.entity.HabitLogEntity

@Database(
    entities = [HabitLogEntity::class],
    version = 1,
    exportSchema = false
)
abstract class DailyDatabase : RoomDatabase() {

    abstract fun habitLogDao(): HabitLogDao

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
