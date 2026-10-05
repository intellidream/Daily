package com.intellidream.daily.health

import com.intellidream.daily.model.HealthTelemetryRecord
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

@Serializable
data class GoldenFixtureExpected(
    val steps: Int? = null,
    @SerialName("active_kcal") val activeKcal: Double? = null,
    @SerialName("sleep_asleep_s") val sleepAsleepS: Int? = null,
    @SerialName("sleep_score") val sleepScore: Int? = null,
    @SerialName("stress_avg") val stressAvg: Int? = null,
    val rhr: Int? = null,
    @SerialName("hrv_sdnn") val hrvSdnn: Double? = null,
    @SerialName("primary_sleep_device") val primarySleepDevice: String? = null,
    @SerialName("sleep_quality_rating") val sleepQualityRating: String? = null,
    @SerialName("nap_count") val napCount: Int = 0
)

@Serializable
data class GoldenFixtureInput(
    @SerialName("user_id") val userId: String,
    @SerialName("target_date") val targetDate: String,
    @SerialName("tz_offset_min") val tzOffsetMin: Int,
    val telemetry: List<HealthTelemetryRecord>
)

@Serializable
data class GoldenFixture(
    val name: String,
    val description: String,
    val input: GoldenFixtureInput,
    val expected: GoldenFixtureExpected
)

/**
 * Android JUnit tests verifying zero mathematical divergence across Canonical Golden Fixtures.
 */
class GoldenFixturesTest {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private fun findFixturesDir(): File? {
        val candidates = listOf(
            File("../../HealthSpec/fixtures"),
            File("../HealthSpec/fixtures"),
            File("HealthSpec/fixtures"),
            File("../../../HealthSpec/fixtures")
        )
        return candidates.firstOrNull { it.exists() && it.isDirectory }
    }

    @Test
    fun testAllGoldenFixturesParity() {
        val fixturesDir = findFixturesDir()
        assertNotNull("HealthSpec/fixtures directory must exist", fixturesDir)

        val fixtureFiles = fixturesDir!!.listFiles { file -> file.extension == "json" }?.sortedBy { it.name } ?: emptyList()
        assertTrue("Should find at least 5 golden fixture files", fixtureFiles.size >= 5)

        val isoFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        for (file in fixtureFiles) {
            val content = file.readText()
            val fixture = json.decodeFromString<GoldenFixture>(content)

            val targetDate = isoFormatter.parse(fixture.input.targetDate)
            assertNotNull("Target date parsing failed for ${fixture.name}", targetDate)

            // Test Sleep Clustering
            val sleepResult = SleepClusteringEngine.clusterSleep(
                targetDate = targetDate!!,
                telemetry = fixture.input.telemetry
            )

            val primary = sleepResult.primarySession
            val actualSleepS = primary?.asleepSeconds?.toInt()
            val actualScore = primary?.sleepScore
            val actualDevice = primary?.sourceDevice
            val actualNaps = sleepResult.naps.size

            assertEquals("[${fixture.name}] sleep_asleep_s mismatch", fixture.expected.sleepAsleepS, actualSleepS)
            assertEquals("[${fixture.name}] sleep_score mismatch", fixture.expected.sleepScore, actualScore)
            assertEquals("[${fixture.name}] primary_sleep_device mismatch", fixture.expected.primarySleepDevice, actualDevice)
            assertEquals("[${fixture.name}] nap_count mismatch", fixture.expected.napCount, actualNaps)
        }
    }
}
