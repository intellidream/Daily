package com.intellidream.daily.cosmos

import android.content.Context
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CosmosConstellation
import com.intellidream.daily.model.CosmosDeepSkyObject
import com.intellidream.daily.model.CosmosStar
import com.intellidream.daily.model.MeteorShower
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

sealed class CosmosSearchResult {
    data class Star(val star: CosmosStar) : CosmosSearchResult()
    data class Constellation(val constellation: CosmosConstellation) : CosmosSearchResult()
    data class DSO(val dso: CosmosDeepSkyObject) : CosmosSearchResult()
    data class Planet(val body: CelestialBody) : CosmosSearchResult()

    val title: String get() = when (this) {
        is Star -> star.nameEn.ifEmpty { star.name }
        is Constellation -> if (constellation.nameLa == constellation.nameEn) constellation.nameLa else "${constellation.nameLa} (${constellation.nameEn})"
        is DSO -> "${dso.catalogNumber} – ${dso.name}"
        is Planet -> "${body.symbol} ${body.displayName}"
    }

    val subtitle: String get() = when (this) {
        is Star -> "Star mag ${star.visualMag} • ${star.constellationCode}"
        is Constellation -> "Constellation • ${constellation.code}"
        is DSO -> "${dso.objectType} • mag ${dso.visualMag}"
        is Planet -> "Solar System Planet"
    }
}

class CosmosCatalogRepository(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    var stars: List<CosmosStar> = emptyList()
        private set
    var constellations: List<CosmosConstellation> = emptyList()
        private set
    var deepSkyObjects: List<CosmosDeepSkyObject> = emptyList()
        private set
    var meteorShowers: List<MeteorShower> = emptyList()
        private set

    private var isLoaded = false

    suspend fun ensureLoaded() = withContext(Dispatchers.IO) {
        if (isLoaded) return@withContext

        try {
            val starsJson = context.assets.open("cosmos/bright_stars.json").bufferedReader().use { it.readText() }
            stars = json.decodeFromString<List<CosmosStar>>(starsJson)
        } catch (_: Exception) {}

        try {
            val constJson = context.assets.open("cosmos/constellations_iau88.json").bufferedReader().use { it.readText() }
            constellations = json.decodeFromString<List<CosmosConstellation>>(constJson)
        } catch (_: Exception) {}

        try {
            val dsoJson = context.assets.open("cosmos/dso_messier.json").bufferedReader().use { it.readText() }
            deepSkyObjects = json.decodeFromString<List<CosmosDeepSkyObject>>(dsoJson)
        } catch (_: Exception) {}

        try {
            val meteorsJson = context.assets.open("cosmos/meteor_showers.json").bufferedReader().use { it.readText() }
            meteorShowers = json.decodeFromString<List<MeteorShower>>(meteorsJson)
        } catch (_: Exception) {}

        isLoaded = true
    }

    fun search(query: String): List<CosmosSearchResult> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()

        val results = mutableListOf<CosmosSearchResult>()

        // Search major planets
        CelestialBody.majorPlanets.forEach { body ->
            if (body.displayName.lowercase().contains(q) || body.name.lowercase().contains(q)) {
                results.add(CosmosSearchResult.Planet(body))
            }
        }

        // Search stars
        stars.forEach { star ->
            if (star.nameRo.lowercase().contains(q) ||
                star.nameEn.lowercase().contains(q) ||
                star.bayer?.lowercase()?.contains(q) == true
            ) {
                results.add(CosmosSearchResult.Star(star))
            }
        }

        // Search constellations
        constellations.forEach { c ->
            if (c.romanianName.lowercase().contains(q) ||
                c.latinName.lowercase().contains(q) ||
                c.code.lowercase().contains(q)
            ) {
                results.add(CosmosSearchResult.Constellation(c))
            }
        }

        // Search DSOs
        deepSkyObjects.forEach { dso ->
            if (dso.catalogNumber.lowercase().contains(q) ||
                dso.commonNameRo.lowercase().contains(q) ||
                dso.commonNameEn.lowercase().contains(q) ||
                dso.objectType.lowercase().contains(q)
            ) {
                results.add(CosmosSearchResult.DSO(dso))
            }
        }

        return results.take(15)
    }
}
