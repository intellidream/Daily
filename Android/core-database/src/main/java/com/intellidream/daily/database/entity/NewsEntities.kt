package com.intellidream.daily.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedSource
import com.intellidream.daily.model.FeedType
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.SavedArticle
import com.intellidream.daily.model.SavedArticleType

@Entity(
    tableName = "rss_subscriptions",
    indices = [
        Index(value = ["user_id"]),
        Index(value = ["url"]),
        Index(value = ["synced_at"])
    ]
)
data class RssSubscriptionEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "url")
    val url: String,

    @ColumnInfo(name = "icon_url")
    val iconUrl: String,

    @ColumnInfo(name = "category")
    val category: String,

    @ColumnInfo(name = "display_order")
    val displayOrder: Int = 0,

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long? = null,

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
) {
    fun toFeedSource(): FeedSource {
        val cat = FeedCategory.fromString(category)
        val feedType = if (url.contains("wp-json", ignoreCase = true)) FeedType.WpJson else FeedType.Rss
        return FeedSource(
            id = id,
            name = name,
            url = url,
            iconUrl = iconUrl,
            type = feedType,
            category = cat,
            displayOrder = displayOrder
        )
    }

    companion object {
        fun fromFeedSource(source: FeedSource, userId: String): RssSubscriptionEntity {
            return RssSubscriptionEntity(
                id = source.id,
                userId = userId,
                name = source.name,
                url = source.url,
                iconUrl = source.iconUrl,
                category = source.category.value,
                displayOrder = source.displayOrder,
                isDeleted = false,
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis(),
                syncedAt = null
            )
        }
    }
}

@Entity(
    tableName = "rss_saved_articles",
    indices = [
        Index(value = ["user_id", "article_type"]),
        Index(value = ["article_url"]),
        Index(value = ["synced_at"])
    ]
)
data class SavedArticleEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String,

    @ColumnInfo(name = "article_url")
    val articleUrl: String,

    @ColumnInfo(name = "title")
    val title: String,

    @ColumnInfo(name = "image_url")
    val imageUrl: String? = null,

    @ColumnInfo(name = "description")
    val description: String? = null,

    @ColumnInfo(name = "author")
    val author: String? = null,

    @ColumnInfo(name = "publication_name")
    val publicationName: String = "News",

    @ColumnInfo(name = "publication_icon_url")
    val publicationIconUrl: String? = null,

    @ColumnInfo(name = "article_type")
    val articleType: String = SavedArticleType.ReadLater.value,

    @ColumnInfo(name = "article_date")
    val articleDate: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long? = null,

    @ColumnInfo(name = "synced_at")
    val syncedAt: Long? = null
) {
    fun toNewsArticle(): NewsArticle {
        return NewsArticle(
            id = articleUrl,
            title = title,
            link = articleUrl,
            publishDate = articleDate,
            imageUrl = imageUrl,
            description = description,
            author = author,
            publicationName = publicationName,
            publicationIconUrl = publicationIconUrl
        )
    }

    companion object {
        fun fromNewsArticle(article: NewsArticle, userId: String, type: SavedArticleType): SavedArticleEntity {
            val deterministicId = SavedArticle.generateDeterministicId(userId, article.link, type)
            return SavedArticleEntity(
                id = deterministicId,
                userId = userId,
                articleUrl = article.link,
                title = article.title,
                imageUrl = article.imageUrl,
                description = article.description,
                author = article.author,
                publicationName = article.publicationName ?: "News",
                publicationIconUrl = article.publicationIconUrl,
                articleType = type.value,
                articleDate = article.publishDate,
                isDeleted = false,
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis(),
                syncedAt = null
            )
        }
    }
}
