package com.intellidream.daily.model

import java.util.UUID

/**
 * Fast, deterministic parser for the TagDoS syntax.
 * 1:1 Kotlin port of iOS DailyCore [TagdosParser.swift].
 *
 * Syntactic rules:
 * - Streams are collections of clusters separated by ` & `
 * - Clusters are sequences of mental action tags separated by `/`
 * - Semantic tokens: `$` or `€` (financial), `!` (urgent), digits (metric/date)
 */
object TagdosParser {

    /**
     * Parses a raw TagDoS line into a fully populated [TagDoStream].
     */
    fun parseStream(
        rawText: String,
        title: String,
        id: String = UUID.randomUUID().toString(),
        streamReminder: Long? = null,
        orderIndex: Int = 0,
        existingStream: TagDoStream? = null
    ): TagDoStream {
        val trimmed = rawText.trim()
        if (trimmed.isEmpty()) {
            return TagDoStream(
                id = id,
                title = title,
                customTitle = existingStream?.customTitle,
                rawText = "",
                clusters = emptyList(),
                streamReminder = streamReminder,
                orderIndex = orderIndex,
                activeMemos = existingStream?.activeMemos ?: "",
                attachments = existingStream?.attachments ?: emptyList()
            )
        }

        // Split by cluster separator: ` & ` (support variable spacing around `&`)
        val rawClusters = trimmed.split("&")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        val parsedClusters = mutableListOf<TagDoCluster>()

        for (rawCluster in rawClusters) {
            // Split cluster by pill separator: `/`
            val rawPillTokens = rawCluster.split("/")
                .map { it.trim() }
                .filter { it.isNotEmpty() }

            val pills = mutableListOf<TagDoPill>()
            for (token in rawPillTokens) {
                // If an existing pill with the same token exists, preserve its completion and notes state
                val existing = existingStream?.allPills?.firstOrNull { it.rawText == token }
                if (existing != null) {
                    pills.add(
                        TagDoPill(
                            id = existing.id,
                            rawText = token,
                            type = existing.type,
                            isCompleted = existing.isCompleted,
                            customReminderDate = existing.customReminderDate,
                            decodedNote = existing.decodedNote
                        )
                    )
                } else {
                    pills.add(TagDoPill(rawText = token))
                }
            }

            if (pills.isNotEmpty()) {
                parsedClusters.add(TagDoCluster(pills = pills, rawText = rawCluster))
            }
        }

        return TagDoStream(
            id = id,
            title = title,
            customTitle = existingStream?.customTitle,
            rawText = trimmed,
            clusters = parsedClusters,
            streamReminder = streamReminder,
            orderIndex = orderIndex,
            activeMemos = existingStream?.activeMemos ?: "",
            attachments = existingStream?.attachments ?: emptyList()
        )
    }

    /**
     * Serializes a [TagDoStream] back to its canonical raw string format.
     */
    fun serializeStream(stream: TagDoStream): String {
        return stream.clusters.joinToString(" & ") { cluster ->
            cluster.pills.joinToString("/") { it.rawText }
        }
    }

    // MARK: - Interactive Mutations

    /**
     * Cycles a pill to the end of its cluster for recurring habits/tasks.
     * Resets completed status for the next cycle.
     */
    fun recyclePillToBack(stream: TagDoStream, pillId: String): TagDoStream {
        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()

        for (clusterIndex in updatedClusters.indices) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            val pillIndex = pills.indexOfFirst { it.id == pillId }
            if (pillIndex != -1) {
                val pill = pills.removeAt(pillIndex)
                pills.add(pill.copy(isCompleted = false))
                val newRawText = pills.joinToString("/") { it.rawText }
                updatedClusters[clusterIndex] = cluster.copy(pills = pills, rawText = newRawText)
                break
            }
        }

        val newRawText = updatedClusters.joinToString(" & ") { it.rawText }
        return stream.copy(
            rawText = newRawText,
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }

    /**
     * Toggles completion status of a pill in-place.
     */
    fun togglePillCompletion(stream: TagDoStream, pillId: String): TagDoStream {
        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()

        for (clusterIndex in updatedClusters.indices) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            val pillIndex = pills.indexOfFirst { it.id == pillId }
            if (pillIndex != -1) {
                val pill = pills[pillIndex]
                pills[pillIndex] = pill.copy(isCompleted = !pill.isCompleted)
                updatedClusters[clusterIndex] = cluster.copy(pills = pills)
                break
            }
        }

        return stream.copy(
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }

    /**
     * Removes a pill from the stream (one-off task).
     */
    fun removePill(stream: TagDoStream, pillId: String): TagDoStream {
        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()

        for (clusterIndex in updatedClusters.indices.reversed()) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            val pillIndex = pills.indexOfFirst { it.id == pillId }
            if (pillIndex != -1) {
                pills.removeAt(pillIndex)
                if (pills.isEmpty()) {
                    updatedClusters.removeAt(clusterIndex)
                } else {
                    val newRawText = pills.joinToString("/") { it.rawText }
                    updatedClusters[clusterIndex] = cluster.copy(pills = pills, rawText = newRawText)
                }
                break
            }
        }

        val newRawText = updatedClusters.joinToString(" & ") { it.rawText }
        return stream.copy(
            rawText = newRawText,
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }

    /**
     * Moves a pill to the very beginning of its cluster (highest priority).
     */
    fun movePillToFront(stream: TagDoStream, pillId: String): TagDoStream {
        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()

        for (clusterIndex in updatedClusters.indices) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            val pillIndex = pills.indexOfFirst { it.id == pillId }
            if (pillIndex != -1) {
                val pill = pills.removeAt(pillIndex)
                pills.add(0, pill)
                val newRawText = pills.joinToString("/") { it.rawText }
                updatedClusters[clusterIndex] = cluster.copy(pills = pills, rawText = newRawText)
                break
            }
        }

        val newRawText = updatedClusters.joinToString(" & ") { it.rawText }
        return stream.copy(
            rawText = newRawText,
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }

    /**
     * Adds a new pill into a specific cluster or creates a new one.
     */
    fun addPill(stream: TagDoStream, clusterIndex: Int, text: String): TagDoStream {
        val cleanText = text.trim()
        if (cleanText.isEmpty()) return stream

        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()
        val newPill = TagDoPill(rawText = cleanText)

        if (updatedClusters.isEmpty()) {
            updatedClusters.add(TagDoCluster(pills = listOf(newPill), rawText = cleanText))
        } else if (clusterIndex in 0 until updatedClusters.count()) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            pills.add(newPill)
            val newRawText = pills.joinToString("/") { it.rawText }
            updatedClusters[clusterIndex] = cluster.copy(pills = pills, rawText = newRawText)
        } else {
            val last = updatedClusters.last()
            val pills = last.pills.toMutableList()
            pills.add(newPill)
            val newRawText = pills.joinToString("/") { it.rawText }
            updatedClusters[updatedClusters.count() - 1] = last.copy(pills = pills, rawText = newRawText)
        }

        val newRawText = updatedClusters.joinToString(" & ") { it.rawText }
        return stream.copy(
            rawText = newRawText,
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }
}
