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
        val usedExistingClusterIds = mutableSetOf<String>()

        for ((clusterIndex, rawCluster) in rawClusters.withIndex()) {
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
                val pillIdSet = pills.map { it.id }.toSet()
                val matchedCluster = existingStream?.clusters?.firstOrNull {
                    !usedExistingClusterIds.contains(it.id) && it.rawText == rawCluster
                } ?: existingStream?.clusters?.firstOrNull {
                    !usedExistingClusterIds.contains(it.id) && it.pills.any { p -> pillIdSet.contains(p.id) }
                } ?: existingStream?.clusters?.getOrNull(clusterIndex)?.takeIf {
                    !usedExistingClusterIds.contains(it.id)
                }

                if (matchedCluster != null) {
                    usedExistingClusterIds.add(matchedCluster.id)
                    parsedClusters.add(
                        TagDoCluster(
                            id = matchedCluster.id,
                            pills = pills,
                            rawText = rawCluster,
                            reminderTime = matchedCluster.reminderTime
                        )
                    )
                } else {
                    parsedClusters.add(TagDoCluster(pills = pills, rawText = rawCluster))
                }
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

    /**
     * Updates the text of an existing pill in-place, re-evaluates its semantic type, and re-serializes rawText.
     */
    fun updatePillText(stream: TagDoStream, pillId: String, newText: String): TagDoStream {
        val cleanText = newText.trim()
            .replace("/", "-")
            .replace("&", "+")
        if (cleanText.isEmpty()) return stream

        val updatedClusters = stream.clusters.map { it.copy(pills = it.pills.toMutableList()) }.toMutableList()
        var didChange = false

        for (clusterIndex in updatedClusters.indices) {
            val cluster = updatedClusters[clusterIndex]
            val pills = cluster.pills.toMutableList()
            val pillIndex = pills.indexOfFirst { it.id == pillId }
            if (pillIndex != -1) {
                val existing = pills[pillIndex]
                pills[pillIndex] = existing.copy(
                    rawText = cleanText,
                    type = TagDoPillType.detect(cleanText)
                )
                val newClusterRaw = pills.joinToString("/") { it.rawText }
                updatedClusters[clusterIndex] = cluster.copy(pills = pills, rawText = newClusterRaw)
                didChange = true
                break
            }
        }

        if (!didChange) return stream
        val newRawText = updatedClusters.joinToString(" & ") { it.rawText }
        return stream.copy(
            rawText = newRawText,
            clusters = updatedClusters,
            updatedAt = System.currentTimeMillis()
        )
    }

    // MARK: - DSL Detection & Import Helpers

    /**
     * Returns true if [text] already conforms to TagDoS DSL (e.g., `MG/GM/TG & FSH/LDL`, `MG/GM & CRR vg/PL 98`, `C$T`, `EXP!`, `5K`).
     */
    fun isAlreadyTagdosDsl(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false

        val lower = trimmed.lowercase()
        if (lower.contains("http://") || lower.contains("https://") || lower.contains("www.")) {
            return false
        }

        if (trimmed.contains("/") || trimmed.contains("&")) {
            val clusters = trimmed.split("&").map { it.trim() }.filter { it.isNotEmpty() }
            if (clusters.isEmpty()) return false

            if (trimmed.contains("/")) {
                var totalTokens = 0
                var hasSpaceInsideToken = false
                var hasMnemonicSignal = false
                for (cluster in clusters) {
                    val tokens = cluster.split("/").map { it.trim() }.filter { it.isNotEmpty() }
                    if (tokens.isEmpty()) return false
                    for (token in tokens) {
                        val words = token.split(Regex("\\s+")).filter { it.isNotEmpty() }
                        if (token.length > 24 || words.size > 3) return false
                        if (words.size > 1) {
                            hasSpaceInsideToken = true
                        }
                        if (token.contains("$") || token.contains("€") || token.contains("!")) {
                            hasMnemonicSignal = true
                        }
                        for (w in words) {
                            val wLetters = w.filter { it.isLetter() }
                            if (wLetters.length >= 2 && wLetters.all { it.isUpperCase() }) {
                                hasMnemonicSignal = true
                            }
                        }
                        totalTokens++
                    }
                }
                if (totalTokens < 2 && clusters.size < 2) return false
                return !hasSpaceInsideToken || hasMnemonicSignal
            } else {
                if (clusters.size < 2) return false
                var hasMnemonicSignal = false
                for (cluster in clusters) {
                    val words = cluster.split(Regex("\\s+")).filter { it.isNotEmpty() }
                    if (cluster.length > 24 || words.size > 3) return false
                    val lettersOnly = cluster.filter { it.isLetter() }
                    val isAllCaps = lettersOnly.isNotEmpty() && lettersOnly.all { it.isUpperCase() }
                    val hasGlyph = cluster.contains("$") || cluster.contains("€") || cluster.contains("!") ||
                        cluster.any { it.isDigit() }
                    if (hasGlyph || isAllCaps || cluster.length <= 5) {
                        hasMnemonicSignal = true
                    }
                }
                return hasMnemonicSignal
            }
        }

        if (trimmed.any { it.isWhitespace() } || trimmed.length > 12) return false
        if (lower.contains(".com")) return false
        val hasSemanticGlyph = trimmed.contains("$") || trimmed.contains("€") || trimmed.contains("!") ||
            trimmed.any { it.isDigit() }
        if (hasSemanticGlyph) return true

        val lettersOnly = trimmed.filter { it.isLetter() }
        val isAllCaps = lettersOnly.isNotEmpty() && lettersOnly.all { it.isUpperCase() }
        return isAllCaps || trimmed.length <= 4
    }

    /**
     * Generates an editable mnemonic tag proposal for natural-language tasks.
     */
    fun proposeMnemonic(title: String, isHighImportance: Boolean = false): String {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return if (isHighImportance) "TASK!" else "TASK"
        if (isAlreadyTagdosDsl(trimmed)) {
            return if (isHighImportance && !trimmed.contains("!") && !trimmed.contains("/") && !trimmed.contains("&")) {
                "$trimmed!"
            } else {
                trimmed
            }
        }

        val stopWords = setOf(
            "the", "a", "an", "to", "for", "of", "in", "on", "at", "and", "or", "with", "my", "this", "that",
            "la", "de", "si", "cu", "pt", "pentru", "pe", "din", "un", "o", "sa"
        )
        val financialWords = setOf(
            "pay", "bill", "bills", "invoice", "tax", "taxes", "bank", "card", "budget", "buy", "rent",
            "salary", "transfer", "money", "cost", "price", "fee", "plata", "factura", "bani", "buget", "eur", "usd", "ron"
        )
        val urgentWords = setOf("urgent", "asap", "important", "deadline", "critical", "immediately")

        val rawTokens = trimmed.split(Regex("[^A-Za-z0-9]+")).filter { it.isNotEmpty() }
        val significant = rawTokens.filter { it.lowercase() !in stopWords }
        val words = significant.ifEmpty { rawTokens }

        val hasEuro = trimmed.contains("€") || rawTokens.any { it.equals("eur", true) || it.equals("euro", true) }
        val hasDollar = trimmed.contains("$") || rawTokens.any { it.lowercase() in financialWords }
        val isUrgent = isHighImportance || trimmed.contains("!") || rawTokens.any { it.lowercase() in urgentWords }

        var base = when {
            words.isEmpty() -> "TASK"
            words.size == 1 -> words[0].take(5).uppercase()
            words.size == 2 -> (words[0].take(3) + words[1].take(3)).take(6).uppercase()
            else -> (words[0].take(2) + words[1].take(2) + words[2].take(2)).take(6).uppercase()
        }

        if (hasEuro && !base.contains("€")) {
            base += "€"
        } else if (hasDollar && !base.contains("$")) {
            base += "$"
        }
        if (isUrgent && !base.contains("!")) {
            base += "!"
        }
        return base
    }

    fun prepareImportItem(
        title: String,
        notes: String? = null,
        isHighImportance: Boolean = false
    ): Triple<String, Boolean, String?> {
        val cleanTitle = title.trim()
        val rawNotes = notes?.trim().orEmpty()
        val cleanNotes = if (rawNotes.equals(cleanTitle, ignoreCase = true)) "" else rawNotes
        val isDsl = isAlreadyTagdosDsl(cleanTitle)
        val tag = if (isDsl) cleanTitle else proposeMnemonic(cleanTitle, isHighImportance)

        return if (isDsl) {
            // Plain notes only without any [DSL] prefix or title duplication
            val memo = cleanNotes.ifEmpty { null }
            Triple(tag, true, memo)
        } else {
            val memo = if (cleanNotes.isEmpty()) "• [$tag] $cleanTitle" else "• [$tag] $cleanTitle — $cleanNotes"
            Triple(tag, false, memo)
        }
    }

    // MARK: - Zero-Egress Reminder Spec Encoding ("HH:mm|0=08:45,1=14:15")

    fun encodeReminderSpec(stream: TagDoStream): String? {
        val fmt = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
        val streamPart = stream.streamReminder?.let { fmt.format(java.util.Date(it)) } ?: ""
        val clusterParts = stream.clusters.mapIndexedNotNull { idx, c ->
            c.reminderTime?.let { "$idx=${fmt.format(java.util.Date(it))}" }
        }
        if (streamPart.isEmpty() && clusterParts.isEmpty()) return null
        if (clusterParts.isEmpty()) return streamPart
        return "$streamPart|${clusterParts.joinToString(",")}"
    }

    fun decodeReminderSpec(raw: String?): Pair<Long?, Map<Int, Long>> {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null to emptyMap()

        fun parseHhMm(token: String): Long? {
            val parts = token.trim().split(":")
            if (parts.size != 2) return null
            val h = parts[0].toIntOrNull() ?: return null
            val m = parts[1].toIntOrNull() ?: return null
            if (h !in 0..23 || m !in 0..59) return null
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.HOUR_OF_DAY, h)
            cal.set(java.util.Calendar.MINUTE, m)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }

        val sections = trimmed.split("|", limit = 2)
        val streamEpoch = sections[0].trim().takeIf { it.isNotEmpty() }?.let { parseHhMm(it) }
        val clusterMap = linkedMapOf<Int, Long>()
        if (sections.size > 1) {
            for (pair in sections[1].split(",")) {
                val kv = pair.split("=", limit = 2)
                if (kv.size == 2) {
                    val idx = kv[0].trim().toIntOrNull()
                    val ts = parseHhMm(kv[1])
                    if (idx != null && ts != null) {
                        clusterMap[idx] = ts
                    }
                }
            }
        }
        return streamEpoch to clusterMap
    }
}
