package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.intellidream.daily.database.entity.SmartLedgerEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SmartLedgerDao {

    @Query("SELECT * FROM smart_ledgers WHERE id = :id LIMIT 1")
    fun getLedger(id: String = "primary_ledger"): Flow<SmartLedgerEntity?>

    @Query("SELECT * FROM smart_ledgers WHERE id = :id LIMIT 1")
    suspend fun getLedgerSync(id: String = "primary_ledger"): SmartLedgerEntity?

    @Upsert
    suspend fun upsert(entity: SmartLedgerEntity)

    @Query("SELECT * FROM smart_ledgers WHERE synced_at IS NULL")
    suspend fun getUnsyncedLedgers(): List<SmartLedgerEntity>

    @Query("UPDATE smart_ledgers SET synced_at = :syncedAt WHERE id = :id")
    suspend fun markSynced(id: String, syncedAt: Long = System.currentTimeMillis())
}
