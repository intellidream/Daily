package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@Serializable
enum class FeedType(val value: String) {
    @SerialName("rss")
    Rss("rss"),
    @SerialName("wpJson")
    WpJson("wpJson")
}

@Serializable
enum class FeedCategory(val value: String, val displayName: String, val iconName: String = "feed") {
    @SerialName("all")
    All("all", "All News", "newspaper"),
    @SerialName("local")
    Local("local", "🇷🇴 Local", "map"),
    @SerialName("markets")
    Markets("markets", "📈 Markets", "trending_up"),
    @SerialName("world")
    World("world", "🌍 World", "public"),
    @SerialName("tech")
    Tech("tech", "💡 Tech", "memory"),
    @SerialName("coding")
    Coding("coding", "💻 Coding", "code"),
    @SerialName("space")
    Space("space", "🚀 Space", "rocket_launch"),
    @SerialName("other")
    Other("other", "📰 Other", "feed");

    companion object {
        fun fromString(str: String): FeedCategory {
            val lower = str.lowercase(Locale.ROOT)
            return entries.firstOrNull { it.value.lowercase(Locale.ROOT) == lower } ?: Tech
        }
    }
}

@Serializable
data class FeedSource(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String,
    val iconUrl: String = "",
    val type: FeedType = FeedType.Rss,
    val category: FeedCategory = FeedCategory.Tech,
    val displayOrder: Int = 0
) {
    val resolvedIconUrl: String
        get() = if (iconUrl.isNotBlank()) {
            iconUrl
        } else {
            val host = try {
                java.net.URI(url).host ?: "rss.com"
            } catch (_: Exception) {
                "rss.com"
            }
            "https://www.google.com/s2/favicons?domain=$host&sz=64"
        }
}

@Serializable
data class NewsArticle(
    val id: String = java.util.UUID.randomUUID().toString(),
    val title: String,
    val link: String,
    val publishDate: Long = System.currentTimeMillis(),
    val imageUrl: String? = null,
    val description: String? = null,
    val content: String? = null,
    val author: String? = null,
    val publicationName: String? = null,
    val publicationIconUrl: String? = null,
    val category: FeedCategory? = null
) {
    val isMediumItem: Boolean
        get() = publicationName?.contains("Medium", ignoreCase = true) == true ||
                link.contains("medium.com", ignoreCase = true)

    val mediumUsername: String?
        get() = extractMediumUsername(this)

    val relativeTimeFormatted: String
        get() {
            val now = System.currentTimeMillis()
            val diff = now - publishDate
            val seconds = diff / 1000
            val minutes = seconds / 60
            val hours = minutes / 60
            val days = hours / 24

            return when {
                seconds < 60 -> "Just now"
                minutes < 60 -> "${minutes}m ago"
                hours < 24 -> "${hours}h ago"
                days < 7 -> "${days}d ago"
                else -> {
                    val sdf = SimpleDateFormat("MMM d", Locale.getDefault())
                    sdf.format(Date(publishDate))
                }
            }
        }
}

fun extractMediumUsername(article: NewsArticle): String? {
    if (!article.link.contains("medium.com", ignoreCase = true)) return null
    return try {
        val uri = java.net.URI(article.link)
        val path = uri.path
        if (path != null && path.startsWith("/@")) {
            val user = path.removePrefix("/@").substringBefore("/")
            if (user.isNotBlank()) user else null
        } else if (uri.host?.contains(".medium.com", ignoreCase = true) == true) {
            val sub = uri.host?.substringBefore(".medium.com")
            if (sub != null && sub != "www" && sub != "api") sub else null
        } else if (article.author?.startsWith("@") == true) {
            article.author.removePrefix("@")
        } else null
    } catch (_: Exception) {
        if (article.author?.startsWith("@") == true) article.author.removePrefix("@") else null
    }
}

@Serializable
enum class SavedArticleType(val value: String) {
    @SerialName("ReadLater")
    ReadLater("ReadLater"),
    @SerialName("Favorite")
    Favorite("Favorite")
}

@Serializable
data class SavedArticle(
    val id: String,
    @SerialName("user_id")
    val userId: String,
    @SerialName("article_url")
    val articleUrl: String,
    val title: String,
    @SerialName("image_url")
    val imageUrl: String? = null,
    val description: String? = null,
    val author: String? = null,
    @SerialName("publication_name")
    val publicationName: String = "News",
    @SerialName("publication_icon_url")
    val publicationIconUrl: String? = null,
    @SerialName("article_type")
    val articleType: String = SavedArticleType.ReadLater.value,
    @SerialName("article_date")
    val articleDate: String = "",
    @SerialName("created_at")
    val createdAt: String = "",
    @SerialName("updated_at")
    val updatedAt: String? = null,
    @SerialName("is_deleted")
    val isDeleted: Boolean = false
) {
    fun toNewsArticle(): NewsArticle {
        val parsedDate = try {
            java.time.Instant.parse(articleDate).toEpochMilli()
        } catch (_: Exception) {
            System.currentTimeMillis()
        }
        return NewsArticle(
            id = articleUrl,
            title = title,
            link = articleUrl,
            publishDate = parsedDate,
            imageUrl = imageUrl,
            description = description,
            author = author,
            publicationName = publicationName,
            publicationIconUrl = publicationIconUrl
        )
    }

    companion object {
        fun generateDeterministicId(userId: String, articleUrl: String, type: SavedArticleType): String {
            val input = "${userId.lowercase(Locale.ROOT)}:$articleUrl:${type.value}"
            val md = MessageDigest.getInstance("MD5")
            val bytes = md.digest(input.toByteArray(Charsets.UTF_8))
            // Generate UUID from 16 bytes MD5 hash
            var msb: Long = 0
            var lsb: Long = 0
            for (i in 0..7) msb = (msb shl 8) or (bytes[i].toLong() and 0xff)
            for (i in 8..15) lsb = (lsb shl 8) or (bytes[i].toLong() and 0xff)
            return UUID(msb, lsb).toString().lowercase(Locale.ROOT)
        }
    }
}

@Serializable
data class RssSubscription(
    val id: String,
    @SerialName("user_id")
    val userId: String,
    val name: String,
    val url: String,
    @SerialName("icon_url")
    val iconUrl: String,
    val category: String = "tech",
    @SerialName("display_order")
    val displayOrder: Int = 0,
    @SerialName("created_at")
    val createdAt: String = "",
    @SerialName("updated_at")
    val updatedAt: String? = null,
    @SerialName("is_deleted")
    val isDeleted: Boolean = false
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
}

@Serializable
data class FeedSearchResult(
    val name: String,
    val url: String,
    val iconUrl: String = "",
    val website: String = ""
) {
    val id: String get() = url
}
