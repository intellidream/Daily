package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * Semantic classification for a TagDoS pill based on embedded glyphs and tokens.
 * Matches iOS [TagDoPillType].
 */
@Serializable
enum class TagDoPillType(val badgeColorHex: String) {
    @SerialName("standard")
    Standard("#00E5FF"),         // Neon Cyan

    @SerialName("financial")
    Financial("#00E676"),        // Neon Emerald Green

    @SerialName("urgent")
    Urgent("#FF2D55"),           // Glowing Ruby Coral

    @SerialName("temporalOrMetric")
    TemporalOrMetric("#FFD600"), // Neon Amber Yellow

    @SerialName("completed")
    Completed("#8E8E93");        // Dimmed Slate Gray

    companion object {
        fun detect(rawText: String): TagDoPillType {
            return when {
                rawText.contains("$") || rawText.contains("€") -> Financial
                rawText.contains("!") -> Urgent
                rawText.any { it.isDigit() } -> TemporalOrMetric
                else -> Standard
            }
        }
    }
}

/**
 * Represents an individual mental tag / action unit within a cluster.
 * Matches iOS [TagDoPill].
 */
@Serializable
data class TagDoPill(
    val id: String = UUID.randomUUID().toString(),
    val rawText: String,
    val type: TagDoPillType = TagDoPillType.detect(rawText),
    val isCompleted: Boolean = false,
    val customReminderDate: Long? = null,
    val decodedNote: String? = null
)

/**
 * A cluster of related sequential actions separated by `/`, grouped under ` & `.
 * Matches iOS [TagDoCluster].
 */
@Serializable
data class TagDoCluster(
    val id: String = UUID.randomUUID().toString(),
    val pills: List<TagDoPill> = emptyList(),
    val rawText: String = ""
) {
    val activePills: List<TagDoPill> get() = pills.filter { !it.isCompleted }
    val completedPills: List<TagDoPill> get() = pills.filter { it.isCompleted }
}

/**
 * Represents a file, document, or image attachment bound to a specific Tagdos stream.
 * Matches iOS [TagDoAttachment].
 */
@Serializable
data class TagDoAttachment(
    val id: String = UUID.randomUUID().toString(),
    val streamNumber: Int,
    val fileName: String,
    val fileType: String,
    val fileSizeBytes: Long,
    val remotePath: String? = null,
    val localFileName: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val isImage: Boolean
        get() = fileType.contains("image", ignoreCase = true) ||
                listOf("jpg", "jpeg", "png", "webp", "gif").any { fileName.endsWith(it, ignoreCase = true) }

    val formattedSize: String
        get() = when {
            fileSizeBytes < 1024 -> "$fileSizeBytes B"
            fileSizeBytes < 1024 * 1024 -> String.format("%.1f KB", fileSizeBytes / 1024.0)
            else -> String.format("%.1f MB", fileSizeBytes / (1024.0 * 1024.0))
        }
}

/**
 * A single TagDoS line / stream representing a prioritized execution queue.
 * Matches iOS [TagDoStream].
 */
@Serializable
data class TagDoStream(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val customTitle: String? = null,
    val rawText: String,
    val clusters: List<TagDoCluster> = emptyList(),
    val streamReminder: Long? = null,
    val orderIndex: Int = 0,
    val activeMemos: String = "",
    val attachments: List<TagDoAttachment> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    /**
     * Resolved display title: uses explicit custom user title if set;
     * otherwise falls back to auto-detected title.
     */
    val displayTitle: String
        get() {
            if (!customTitle.isNullOrBlank()) return customTitle.trim()
            if (title.isNotBlank()) return title.trim()
            return autoDetectedTitle
        }

    /**
     * Automatically detects a meaningful stream title from tags, keywords, and stream order.
     */
    val autoDetectedTitle: String
        get() {
            val streamNum = orderIndex + 1
            val upperText = rawText.uppercase()

            // 1. Domain detection from known keywords
            if (upperText.contains("WRK") || upperText.contains("PRJ") || upperText.contains("CODE") ||
                upperText.contains("BUG") || upperText.contains("DEV") || upperText.contains("MET")
            ) {
                return "Stream $streamNum: Work & Code"
            }
            if (upperText.contains("FIT") || upperText.contains("GYM") || upperText.contains("RUN") ||
                upperText.contains("PROT") || upperText.contains("SLP") || upperText.contains("CREAT")
            ) {
                return "Stream $streamNum: Health & Fitness"
            }
            if (upperText.contains("FIN") || upperText.contains("CARD") || upperText.contains("CASH") ||
                upperText.contains("INV") || upperText.contains("STK") || upperText.contains("C\$T") || upperText.contains("EUR")
            ) {
                return "Stream $streamNum: Finances & Bills"
            }
            if (upperText.contains("HOM") || upperText.contains("ORD") || upperText.contains("CLN") ||
                upperText.contains("BUY") || upperText.contains("MKT") || upperText.contains("GROC")
            ) {
                return "Stream $streamNum: Home & Life"
            }
            if (upperText.contains("MG") || upperText.contains("GM") || upperText.contains("TG") ||
                upperText.contains("FSH") || upperText.contains("LDL")
            ) {
                return "Stream $streamNum: Daily Ops"
            }

            // 2. Fallback to driving pill tag if present
            val driving = drivingPill?.rawText
            if (!driving.isNullOrBlank()) {
                return "Stream $streamNum: $driving Focus"
            }

            // 3. Slot default fallback
            return when (streamNum) {
                1 -> "Stream 1: Daily Ops"
                2 -> "Stream 2: Work & Code"
                3 -> "Stream 3: Health & Fitness"
                4 -> "Stream 4: Finances & Bills"
                5 -> "Stream 5: Home & Life"
                else -> "Stream $streamNum"
            }
        }

    val allPills: List<TagDoPill> get() = clusters.flatMap { it.pills }
    val activePills: List<TagDoPill> get() = clusters.flatMap { it.activePills }
    val drivingPill: TagDoPill? get() = activePills.firstOrNull()
}

/**
 * Standalone Quick Note with Markdown content, pinning, and tags.
 * Matches iOS [TagDoQuickNote].
 */
@Serializable
data class TagDoQuickNote(
    val id: String = UUID.randomUUID().toString(),
    val userId: String? = null,
    val title: String = "",
    val content: String = "",
    val isPinned: Boolean = false,
    val tags: List<String> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val displayTitle: String
        get() {
            if (title.isNotBlank()) return title.trim()
            val firstLine = content.lines().firstOrNull { it.isNotBlank() }
            if (firstLine != null) {
                val clean = firstLine.replace("#", "").trim()
                return if (clean.isEmpty()) "Untitled Note" else clean
            }
            return "Untitled Note"
        }

    val previewSnippet: String
        get() {
            val lines = content.lines().filter { it.isNotBlank() }
            return if (lines.size > 1) {
                lines.drop(1).joinToString(" ")
            } else {
                content
            }
        }
}

/**
 * Action target wrapper for sheet interactions.
 */
data class TagDoPillAction(
    val streamId: String,
    val pill: TagDoPill
)
