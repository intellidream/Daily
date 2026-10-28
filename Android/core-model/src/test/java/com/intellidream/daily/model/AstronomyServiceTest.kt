package com.intellidream.daily.model

import org.junit.Assert.*
import org.junit.Test

class AstronomyServiceTest {

    @Test
    fun testCoordinatesSunAndMoon() {
        // Bucharest coordinates (44.4323° N, 26.1063° E)
        val lat = 44.4323
        val lon = 26.1063

        val sun = AstronomyService.coordinates(CelestialBody.SUN, lat, lon)
        assertNotNull(sun)
        assertTrue("Sun distance should be approx 0.98 - 1.02 AU", sun.distanceAU in 0.95..1.05)
        assertTrue("Sun azimuth should be in [0, 360]", sun.azimuthDegrees in 0.0..360.0)
        assertTrue("Sun altitude should be in [-90, 90]", sun.altitudeDegrees in -90.0..90.0)

        val moon = AstronomyService.coordinates(CelestialBody.MOON, lat, lon)
        assertNotNull(moon)
        assertTrue("Moon altitude should be in [-90, 90]", moon.altitudeDegrees in -90.0..90.0)
    }

    @Test
    fun testMoonPhase() {
        val moon = AstronomyService.moonPhase()
        assertNotNull(moon)
        assertTrue("Phase angle should be in [0, 360]", moon.phaseAngleDegrees in 0.0..360.0)
        assertTrue("Illuminated fraction in [0, 1]", moon.illuminatedFraction in 0.0..1.0)
        assertTrue("Illumination percent in [0, 100]", moon.illuminationPercent in 0..100)
        assertTrue("Distance km should be around 350,000 - 410,000", moon.distanceKm in 350_000.0..420_000.0)
    }

    @Test
    fun testStargazingEvaluation() {
        val lat = 44.4323
        val lon = 26.1063

        val conditions = AstronomyService.evaluateStargazingConditions(
            latitude = lat,
            longitude = lon,
            cloudCoverTotal = 10,
            cloudCoverLow = 5,
            cloudCoverMid = 5,
            cloudCoverHigh = 10,
            bortleClass = 4
        )

        assertNotNull(conditions)
        assertTrue("Score should be between 0 and 100", conditions.score in 0..100)
        assertTrue("NELM should be positive", conditions.limitingMagnitude > 2.0)
        assertNotNull(conditions.narrativeAdvice)
    }

    @Test
    fun testStereographicProjection() {
        val lat = 44.4323
        val lon = 26.1063
        val now = System.currentTimeMillis()

        // Test projection facing North (azimuth 0, altitude 45)
        val proj = AstronomyService.projectStereographic(
            raHours = 2.5,
            decDegrees = 89.0, // Near Polaris
            observerLatitudeDegrees = lat,
            observerLongitudeDegrees = lon,
            millis = now,
            cameraAzimuthDegrees = 0.0,
            cameraAltitudeDegrees = 45.0,
            cameraRollDegrees = 0.0,
            fovDegrees = 60.0,
            viewportWidth = 1080.0,
            viewportHeight = 1920.0
        )

        // Polaris should be visible or within projected coordinates
        if (proj != null) {
            val (x, y, isVis) = proj
            assertTrue("x should be a valid number", !x.isNaN())
            assertTrue("y should be a valid number", !y.isNaN())
        }
    }
}
