package com.intellidream.daily.wearos.domain.util

import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.Date
import java.util.Locale

object HabitDateParser {
    fun parseToLocalDate(raw: String?): LocalDate? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        val normalized = trimmed.replace(" ", "T")

        // 1. Try standard OffsetDateTime (e.g. 2026-09-02T20:12:42.456+00:00)
        try {
            return OffsetDateTime.parse(normalized).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
        } catch (_: Exception) {}

        // 2. Try Instant (e.g. 2026-09-02T20:12:42.456Z)
        try {
            return Instant.parse(normalized).atZone(ZoneId.systemDefault()).toLocalDate()
        } catch (_: Exception) {}

        // 3. Fallback to SimpleDateFormat with common PostgreSQL formats
        val patterns = arrayOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ssXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        )
        for (pattern in patterns) {
            try {
                val sdf = SimpleDateFormat(pattern, Locale.US)
                val d: Date? = sdf.parse(trimmed)
                if (d != null) {
                    return Instant.ofEpochMilli(d.time).atZone(ZoneId.systemDefault()).toLocalDate()
                }
            } catch (_: Exception) {}
        }
        return null
    }
}
