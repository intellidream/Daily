package com.intellidream.daily.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant
import kotlin.math.cos
import kotlin.math.sin

class AstronomyServiceTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable
    private data class ExpectedPoint(val x: Double, val y: Double, val cz: Double)

    @Serializable
    private data class CameraCase(
        val name: String,
        val camAz: Double,
        val camAlt: Double,
        val fov: Double,
        val targetAz: Double,
        val targetAlt: Double,
        val width: Double,
        val height: Double,
        val expected: ExpectedPoint? = null
    )

    @Serializable
    private data class StarCase(
        val name: String,
        val utc: String,
        val lat: Double,
        val lon: Double,
        val hip: Int,
        val raHours: Double,
        val decDeg: Double,
        val expectedAzDeg: Double,
        val expectedAltDeg: Double,
        val expectedHorNWZ: List<Double>
    )

    @Serializable
    private data class MoonCase(
        val utc: String,
        val lat: Double,
        val lon: Double,
        val expectedGeoDistanceKm: Double,
        val expectedTopoDistanceKm: Double,
        val expectedPhaseFraction: Double,
        val expectedBrightLimbDeg: Double
    )

    @Serializable
    private data class GalileanExpected(
        val name: String,
        val offsetRightRadii: Double,
        val offsetUpRadii: Double,
        val depthRadii: Double
    )

    @Serializable
    private data class JupiterMoonsCase(
        val utc: String,
        val lat: Double,
        val lon: Double,
        val moons: List<GalileanExpected>
    )

    @Serializable
    private data class Sgp4TopocentricExpected(
        val utc: String,
        val lat: Double,
        val lon: Double,
        val elevM: Double,
        val azDeg: Double,
        val altDeg: Double,
        val rangeKm: Double
    )

    @Serializable
    private data class Sgp4Case(
        val omm: CelesTrakOmmRecord,
        val temeAtEpochKm: List<Double>,
        val temePlus45MinKm: List<Double>,
        val topocentricPlus45Min: Sgp4TopocentricExpected
    )

    @Serializable
    private data class ScoreCase(
        val name: String,
        val cloudLow: Double,
        val cloudMid: Double,
        val cloudHigh: Double,
        val moonIllum: Double,
        val moonAltDeg: Double,
        val bortle: Int,
        val seeingArcsec: Double,
        val tempC: Double,
        val dewPointC: Double,
        val expectedScore: Int
    )

    @Serializable
    private data class GoldenFixture(
        val cameraProjectionCases: List<CameraCase>,
        val starEqjToHorCases: List<StarCase>,
        val moonMetricsCase: MoonCase,
        val jupiterGalileanMoonsCase: JupiterMoonsCase,
        val sgp4IssCase: Sgp4Case,
        val stargazingScoreCases: List<ScoreCase>
    )

    private fun resolveRepoRoot(): File {
        var dir = File(System.getProperty("user.dir") ?: ".")
        repeat(4) {
            if (File(dir, "Tests/Fixtures/cosmos_golden_vectors.json").exists()) return dir
            dir = dir.parentFile ?: return dir
        }
        return dir
    }

    private fun loadFixture(): GoldenFixture {
        val file = File(resolveRepoRoot(), "Tests/Fixtures/cosmos_golden_vectors.json")
        assertTrue("Golden fixture must exist at ${file.absolutePath}", file.exists())
        return json.decodeFromString(file.readText())
    }

    @Test
    fun testGoldenCameraProjectionNorthEastSouthWestZenithWraparound() {
        val fixture = loadFixture()
        for (c in fixture.cameraProjectionCases) {
            val actual = AstronomyService.projectHorizontal(
                azimuthDegrees = c.targetAz,
                altitudeDegrees = c.targetAlt,
                cameraAzimuthDegrees = c.camAz,
                cameraAltitudeDegrees = c.camAlt,
                fovDegrees = c.fov,
                viewportWidth = c.width,
                viewportHeight = c.height
            )
            if (c.expected != null) {
                assertNotNull("Expected visible projection for ${c.name}", actual)
                assertEquals("X mismatch in ${c.name}", c.expected.x, actual!!.first, 0.02)
                assertEquals("Y mismatch in ${c.name}", c.expected.y, actual.second, 0.02)
            } else {
                assertNull("Expected behind-camera null for ${c.name}", actual)
            }
        }
    }

    @Test
    fun testGoldenStarEQJToHorAndMatrixCentering() {
        val fixture = loadFixture()
        for (sc in fixture.starEqjToHorCases) {
            val ms = Instant.parse(sc.utc).toEpochMilli()
            val t = AstronomyService.makeTime(ms)
            val res = AstronomyService.starHorizontalCoordinates(
                raHours = sc.raHours,
                decDegrees = sc.decDeg,
                latitude = sc.lat,
                longitude = sc.lon,
                time = t,
                includeRefraction = true
            )
            assertEquals("Azimuth mismatch for ${sc.name}", sc.expectedAzDeg, res.azimuthDegrees, 0.01)
            assertEquals("Altitude mismatch for ${sc.name}", sc.expectedAltDeg, res.altitudeDegrees, 0.01)
            assertEquals(sc.expectedHorNWZ[0], res.hx, 1e-4)
            assertEquals(sc.expectedHorNWZ[1], res.hy, 1e-4)
            assertEquals(sc.expectedHorNWZ[2], res.hz, 1e-4)

            val mat = AstronomyService.makeProjectionMatrix(
                observerLatitudeDegrees = sc.lat,
                observerLongitudeDegrees = sc.lon,
                millis = ms,
                cameraAzimuthDegrees = res.azimuthDegrees,
                cameraAltitudeDegrees = res.altitudeDegrees,
                fovDegrees = 60.0,
                viewportWidth = 1000.0,
                viewportHeight = 800.0
            )
            val raRad = Math.toRadians(sc.raHours * 15.0)
            val decRad = Math.toRadians(sc.decDeg)
            val p = mat.projectEQJUnitVector(cos(decRad) * cos(raRad), cos(decRad) * sin(raRad), sin(decRad))
            assertNotNull(p)
            assertEquals(500.0, p!!.x, 3.0)
            assertEquals(400.0, p.y, 3.0)
        }
    }

    @Test
    fun testGoldenMoonDistanceBrightLimbAndGalileanMoons() {
        val fixture = loadFixture()
        val mc = fixture.moonMetricsCase
        val mMs = Instant.parse(mc.utc).toEpochMilli()
        val moon = AstronomyService.moonPhase(AstronomyService.makeTime(mMs), mc.lat, mc.lon)
        assertTrue(moon.distanceKm in 350_000.0..410_000.0)
        assertEquals(mc.expectedGeoDistanceKm, moon.distanceKm, 5.0)
        assertEquals(mc.expectedTopoDistanceKm, moon.topocentricDistanceKm!!, 5.0)
        assertEquals(mc.expectedPhaseFraction, moon.illuminatedFraction, 0.001)
        assertEquals(mc.expectedBrightLimbDeg, moon.brightLimbAngleDegrees, 0.05)

        val jc = fixture.jupiterGalileanMoonsCase
        val jMs = Instant.parse(jc.utc).toEpochMilli()
        val moons = AstronomyService.jupiterMoons(AstronomyService.makeTime(jMs), jc.lat, jc.lon).all
        assertEquals(4, moons.size)
        for (i in moons.indices) {
            assertEquals(jc.moons[i].name, moons[i].name)
            assertEquals(jc.moons[i].offsetRightRadii, moons[i].xRadius, 0.02)
            assertEquals(jc.moons[i].offsetUpRadii, moons[i].yRadius, 0.02)
            assertEquals(jc.moons[i].depthRadii, moons[i].depthRadius, 0.02)
        }
    }

    @Test
    fun testGoldenSGP4PropagatorAndStargazingScore() {
        val fixture = loadFixture()
        val sc = fixture.sgp4IssCase
        val teme0 = SGP4Propagator.propagateTEMEKm(sc.omm, 0.0)
        assertNotNull(teme0)
        assertEquals(sc.temeAtEpochKm[0], teme0!!.first, 0.05)
        assertEquals(sc.temeAtEpochKm[1], teme0.second, 0.05)
        assertEquals(sc.temeAtEpochKm[2], teme0.third, 0.05)

        val teme45 = SGP4Propagator.propagateTEMEKm(sc.omm, 45.0)
        assertNotNull(teme45)
        assertEquals(sc.temePlus45MinKm[0], teme45!!.first, 0.05)
        assertEquals(sc.temePlus45MinKm[1], teme45.second, 0.05)
        assertEquals(sc.temePlus45MinKm[2], teme45.third, 0.05)

        val ms45 = Instant.parse(sc.topocentricPlus45Min.utc).toEpochMilli()
        val livePos = SGP4Propagator.livePosition(
            sc.omm,
            ms45,
            sc.topocentricPlus45Min.lat,
            sc.topocentricPlus45Min.lon,
            sc.topocentricPlus45Min.elevM
        )
        assertNotNull(livePos)
        assertEquals(sc.topocentricPlus45Min.azDeg, livePos!!.azimuthDegrees, 0.05)
        assertEquals(sc.topocentricPlus45Min.altDeg, livePos.altitudeDegrees, 0.05)
        assertEquals(sc.topocentricPlus45Min.rangeKm, livePos.rangeKm, 0.5)

        for (scoreCase in fixture.stargazingScoreCases) {
            val actual = AstronomyService.computeDeterministicSkyScore(
                scoreCase.cloudLow, scoreCase.cloudMid, scoreCase.cloudHigh,
                scoreCase.moonIllum, scoreCase.moonAltDeg, scoreCase.bortle,
                scoreCase.seeingArcsec, scoreCase.tempC, scoreCase.dewPointC
            )
            assertEquals("Score mismatch in ${scoreCase.name}", scoreCase.expectedScore, actual)
        }
    }

    @Test
    fun testCanonicalAndroidAssetsSchemaIntegrity() {
        val assetsDir = File(resolveRepoRoot(), "Android/app/src/main/assets/cosmos")
        assertTrue(assetsDir.exists())

        val starBytes = File(assetsDir, "stars_mag70.bin").readBytes()
        val bb = ByteBuffer.wrap(starBytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals('D'.code.toByte(), bb.get())
        assertEquals('C'.code.toByte(), bb.get())
        assertEquals('S'.code.toByte(), bb.get())
        assertEquals('T'.code.toByte(), bb.get())
        bb.short; bb.short
        val starCount = bb.int
        assertTrue("Expected >= 15,000 Hipparcos stars, got $starCount", starCount >= 15_000)

        val starNames = json.decodeFromString<List<StarDesignationRecord>>(
            File(assetsDir, "star_names_iau.json").readText()
        )
        assertTrue("Expected >= 3,000 star designations, got ${starNames.size}", starNames.size >= 3_000)
        assertEquals("Sirius", starNames.firstOrNull { it.hip == 32349 }?.name)

        val constellations = json.decodeFromString<List<CosmosConstellation>>(
            File(assetsDir, "constellations_iau88.json").readText()
        )
        assertEquals(88, constellations.size)

        val dsos = json.decodeFromString<List<CosmosDeepSkyObject>>(
            File(assetsDir, "dso_catalog.json").readText()
        )
        assertEquals(219, dsos.size)

        val showers = json.decodeFromString<List<MeteorShower>>(
            File(assetsDir, "meteor_showers_iau.json").readText()
        )
        assertEquals(22, showers.size)

        val asterisms = json.decodeFromString<List<CosmosAsterism>>(
            File(assetsDir, "asterisms.json").readText()
        )
        assertEquals(14, asterisms.size)

        assertEquals("Cosmos & Observatory", DashboardWidgetType.Cosmos.title)
    }
}
