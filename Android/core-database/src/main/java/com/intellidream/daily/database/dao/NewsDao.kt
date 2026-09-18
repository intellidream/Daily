package com.intellidream.daily.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.intellidream.daily.database.entity.RssSubscriptionEntity
import com.intellidream.daily.database.entity.SavedArticleEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface NewsDao {

    // MARK: - Subscriptions

    @Query("SELECT * FROM rss_subscriptions WHERE user_id = :userId AND is_deleted = 0 ORDER BY display_order ASC")
    fun observeSubscriptions(userId: String): Flow<List<RssSubscriptionEntity>>

    @Query("SELECT * FROM rss_subscriptions WHERE user_id = :userId AND is_deleted = 0 ORDER BY display_order ASC")
    suspend fun getSubscriptions(userId: String): List<RssSubscriptionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSubscription(subscription: RssSubscriptionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSubscriptions(subscriptions: List<RssSubscriptionEntity>)

    @Query("UPDATE rss_subscriptions SET is_deleted = 1, updated_at = :timestamp, synced_at = NULL WHERE id = :id")
    suspend fun markSubscriptionDeleted(id: String, timestamp: Long = System.currentTimeMillis())

    @Query("DELETE FROM rss_subscriptions WHERE id = :id")
    suspend fun deleteSubscriptionPermanently(id: String)

    @Query("SELECT * FROM rss_subscriptions WHERE synced_at IS NULL")
    suspend fun getUnsyncedSubscriptions(): List<RssSubscriptionEntity>

    @Query("UPDATE rss_subscriptions SET synced_at = :timestamp WHERE id IN (:ids)")
    suspend fun markSubscriptionsSynced(ids: List<String>, timestamp: Long)

    // MARK: - Saved Articles (Read Later / Favorites)

    @Query("SELECT * FROM rss_saved_articles WHERE user_id = :userId AND article_type = :type AND is_deleted = 0 ORDER BY created_at DESC")
    fun observeSavedArticles(userId: String, type: String): Flow<List<SavedArticleEntity>>

    @Query("SELECT * FROM rss_saved_articles WHERE user_id = :userId AND is_deleted = 0 ORDER BY created_at DESC")
    suspend fun getAllSavedArticles(userId: String): List<SavedArticleEntity>

    @Query("SELECT * FROM rss_saved_articles WHERE user_id = :userId AND article_url = :url AND article_type = :type LIMIT 1")
    suspend fun getSavedArticle(userId: String, url: String, type: String): SavedArticleEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSavedArticle(article: SavedArticleEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSavedArticles(articles: List<SavedArticleEntity>)

    @Query("SELECT * FROM rss_saved_articles WHERE synced_at IS NULL")
    suspend fun getUnsyncedSavedArticles(): List<SavedArticleEntity>

    @Query("UPDATE rss_saved_articles SET synced_at = :timestamp WHERE id IN (:ids)")
    suspend fun markSavedArticlesSynced(ids: List<String>, timestamp: Long)
}
