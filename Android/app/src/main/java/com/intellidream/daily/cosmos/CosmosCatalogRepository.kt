package com.intellidream.daily.cosmos

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CosmosAsterism
import com.intellidream.daily.model.CosmosConstellation
import com.intellidream.daily.model.CosmosConstellationBorderArc
import com.intellidream.daily.model.CosmosDeepSkyObject
import com.intellidream.daily.model.CosmosStar
import com.intellidream.daily.model.MeteorShower
import com.intellidream.daily.model.MilkyWayContourLayer
import com.intellidream.daily.model.PackedStarCatalog
import com.intellidream.daily.model.StarDesignationRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

sealed class CosmosSearchResult {
    data class Star(val star: CosmosStar) : CosmosSearchResult()
    data class Constellation(val constellation: CosmosConstellation) : CosmosSearchResult()
    data class Asterism(val asterism: CosmosAsterism) : CosmosSearchResult()
    data class DSO(val dso: CosmosDeepSkyObject) : CosmosSearchResult()
    data class Planet(val body: CelestialBody) : CosmosSearchResult()
    data class Shower(val shower: MeteorShower) : CosmosSearchResult()
    object IssStation : CosmosSearchResult()

    val objectId: String
        get() = when (this) {
            is Star -> if (star.hip > 0) "HIP-${star.hip}" else "STAR-${star.name}"
            is Constellation -> "CONST-${constellation.id}"
            is Asterism -> "AST-${asterism.id}"
            is DSO -> dso.id
            is Planet -> "BODY-${body.name}"
            is Shower -> "SHOWER-${shower.id}"
            IssStation -> "SAT-25544"
        }

    val categoryKey: String
        get() = when (this) {
            is Star -> "star"
            is Constellation -> "constellation"
            is Asterism -> "asterism"
            is DSO -> "dso"
            is Planet -> "planet"
            is Shower -> "meteor_shower"
            IssStation -> "satellite"
        }

    val title: String
        get() = when (this) {
            is Star -> star.name
            is Constellation -> if (constellation.nameLa.equals(constellation.nameEn, ignoreCase = true)) {
                constellation.nameLa
            } else {
                "${constellation.nameLa} (${constellation.nameEn})"
            }
            is Asterism -> asterism.name
            is DSO -> "${dso.id} · ${dso.name}"
            is Planet -> "${body.symbol} ${body.displayName}"
            is Shower -> "${shower.name} Meteor Shower"
            IssStation -> "ISS (Zarya)"
        }

    val subtitle: String
        get() = when (this) {
            is Star -> {
                val bayer = star.bayer?.takeIf { it.isNotBlank() && !it.contains("undefined") }
                if (bayer != null) "Star · $bayer ${star.constellation} · mag ${"%.2f".format(star.mag)}"
                else "Star · ${star.constellation} · mag ${"%.2f".format(star.mag)}"
            }
            is Constellation -> "IAU Constellation · ${constellation.code}"
            is Asterism -> "Asterism · ${asterism.season.ifBlank { "All-Sky Pattern" }}"
            is DSO -> "${dso.type} · ${dso.constellation} · mag ${"%.1f".format(dso.visualMag)}"
            is Planet -> when (body) {
                CelestialBody.SUN -> "Host Star (G2V)"
                CelestialBody.MOON -> "Earth's Natural Satellite"
                else -> "Solar System Planet"
            }
            is Shower -> "Peak ${monthShort(shower.peakMonth)} ${shower.peakDay} · ZHR ${shower.zhr}"
            IssStation -> "Low-Earth Orbit · NORAD 25544"
        }

    private fun monthShort(m: Int): String {
        val months = arrayOf("", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        return months.getOrElse(m) { "Peak" }
    }
}

class CosmosCatalogRepository(private val context: Context) {
    companion object {
        @Volatile
        private var instance: CosmosCatalogRepository? = null

        fun getInstance(context: Context): CosmosCatalogRepository {
            return instance ?: synchronized(this) {
                instance ?: CosmosCatalogRepository(context.applicationContext).also { instance = it }
            }
        }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val loadMutex = Mutex()
    private val thumbnailCache = ConcurrentHashMap<String, ImageBitmap>()

    @Volatile
    var packedStars: PackedStarCatalog = PackedStarCatalog.EMPTY
        private set

    @Volatile
    var starDesignationsByHip: Map<Int, StarDesignationRecord> = emptyMap()
        private set

    @Volatile
    var stars: List<CosmosStar> = emptyList()
        private set

    @Volatile
    var constellations: List<CosmosConstellation> = emptyList()
        private set

    @Volatile
    var constellationBorders: List<CosmosConstellationBorderArc> = emptyList()
        private set

    @Volatile
    var asterisms: List<CosmosAsterism> = emptyList()
        private set

    @Volatile
    var deepSkyObjects: List<CosmosDeepSkyObject> = emptyList()
        private set

    @Volatile
    var meteorShowers: List<MeteorShower> = emptyList()
        private set

    @Volatile
    var milkyWayLayers: List<MilkyWayContourLayer> = emptyList()
        private set

    @Volatile
    private var bortleBytes: ByteArray? = null

    @Volatile
    var isLoaded: Boolean = false
        private set

    suspend fun ensureLoaded() {
        if (isLoaded) return
        loadMutex.withLock {
            if (isLoaded) return
            withContext(Dispatchers.IO) {
                packedStars = loadBinaryStars()
                starDesignationsByHip = loadStarDesignations()
                constellations = loadJsonAsset("cosmos/constellations_iau88.json") ?: emptyList()
                constellationBorders = loadJsonAsset("cosmos/constellation_borders.json") ?: emptyList()
                asterisms = loadJsonAsset("cosmos/asterisms.json") ?: emptyList()
                deepSkyObjects = loadJsonAsset("cosmos/dso_catalog.json") ?: emptyList()
                meteorShowers = loadJsonAsset("cosmos/meteor_showers_iau.json") ?: emptyList()
                milkyWayLayers = loadMilkyWayIsophotes()
                bortleBytes = runCatching {
                    context.assets.open("cosmos/bortle_world_grid.bin").use { it.readBytes() }
                }.getOrNull()

                stars = buildBrightStarsList(packedStars, starDesignationsByHip, constellations)
                isLoaded = true
            }
        }
    }

    fun bortleClass(latitude: Double, longitude: Double): Int {
        val data = bortleBytes ?: runCatching {
            context.assets.open("cosmos/bortle_world_grid.bin").use { it.readBytes() }.also { bortleBytes = it }
        }.getOrNull()
        if (data == null || data.size < 16 + 129_600) return 5
        val y = floor((latitude + 90.0) * 2.0).toInt().coerceIn(0, 359)
        val normLon = ((longitude + 180.0) % 360.0 + 360.0) % 360.0
        val x = floor(normLon * 2.0).toInt().coerceIn(0, 719)
        val cellIdx = y * 720 + x
        val byteIdx = 16 + (cellIdx ushr 1)
        val packed = data[byteIdx].toInt() and 0xFF
        val v = if ((cellIdx and 1) == 0) (packed ushr 4) else (packed and 0x0F)
        return v.coerceIn(1, 9)
    }

    fun loadDsoThumbnail(relativePath: String?): ImageBitmap? {
        if (relativePath.isNullOrBlank()) return null
        thumbnailCache[relativePath]?.let { return it }
        val clean = relativePath.removePrefix("/")
        val assetPath = if (clean.startsWith("cosmos/")) clean else "cosmos/$clean"
        val bmp = runCatching {
            context.assets.open(assetPath).use { stream ->
                BitmapFactory.decodeStream(stream)?.asImageBitmap()
            }
        }.getOrNull()
        if (bmp != null) {
            thumbnailCache[relativePath] = bmp
        }
        return bmp
    }

    fun search(query: String): List<CosmosSearchResult> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()

        val results = ArrayList<CosmosSearchResult>(24)

        if ("iss".contains(q) || "station".contains(q) || "zarya".contains(q) || "25544".contains(q)) {
            results.add(CosmosSearchResult.IssStation)
        }

        // Sun, Moon & Major Planets
        CelestialBody.entries.forEach { body ->
            if (body.displayName.lowercase().contains(q) || body.name.lowercase().contains(q)) {
                results.add(CosmosSearchResult.Planet(body))
            }
        }

        // Named & Bright Stars
        stars.forEach { star ->
            if (star.name.lowercase().contains(q) ||
                star.constellation.lowercase().contains(q) ||
                star.bayer?.lowercase()?.contains(q) == true ||
                "hip ${star.hip}" == q
            ) {
                results.add(CosmosSearchResult.Star(star))
            }
        }

        // 88 Official IAU Constellations
        constellations.forEach { c ->
            if (c.nameLa.lowercase().contains(q) ||
                c.nameEn.lowercase().contains(q) ||
                c.code.lowercase() == q ||
                c.id.lowercase() == q
            ) {
                results.add(CosmosSearchResult.Constellation(c))
            }
        }

        // 14 Asterisms
        asterisms.forEach { a ->
            if (a.name.lowercase().contains(q) || a.id.lowercase().contains(q)) {
                results.add(CosmosSearchResult.Asterism(a))
            }
        }

        // 219 Messier + Caldwell Deep-Sky Objects
        deepSkyObjects.forEach { dso ->
            if (dso.id.lowercase().contains(q) ||
                dso.name.lowercase().contains(q) ||
                dso.ngcIc?.lowercase()?.contains(q) == true ||
                dso.type.lowercase().contains(q)
            ) {
                results.add(CosmosSearchResult.DSO(dso))
            }
        }

        // 22 Meteor Showers
        meteorShowers.forEach { s ->
            if (s.name.lowercase().contains(q) || s.id.lowercase() == q) {
                results.add(CosmosSearchResult.Shower(s))
            }
        }

        return results.take(24)
    }

    private inline fun <reified T> loadJsonAsset(assetPath: String): T? {
        return runCatching {
            val text = context.assets.open(assetPath).bufferedReader().use { it.readText() }
            json.decodeFromString<T>(text)
        }.getOrNull()
    }

    private fun loadBinaryStars(): PackedStarCatalog {
        val raw = runCatching {
            context.assets.open("cosmos/stars_mag70.bin").use { it.readBytes() }
        }.getOrNull() ?: return PackedStarCatalog.EMPTY

        if (raw.size < 16) return PackedStarCatalog.EMPTY
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        val m0 = buf.get().toInt()
        val m1 = buf.get().toInt()
        val m2 = buf.get().toInt()
        val m3 = buf.get().toInt()
        if (m0 != 'D'.code || m1 != 'C'.code || m2 != 'S'.code || m3 != 'T'.code) {
            return PackedStarCatalog.EMPTY
        }
        buf.short // version
        buf.short // flags
        val count = buf.int
        buf.int // reserved
        if (count <= 0 || raw.size < 16 + count * 32) return PackedStarCatalog.EMPTY

        val hipIds = IntArray(count)
        val ux = FloatArray(count)
        val uy = FloatArray(count)
        val uz = FloatArray(count)
        val raHours = FloatArray(count)
        val decDegrees = FloatArray(count)
        val vMag = FloatArray(count)
        val bv = FloatArray(count)
        val constIdx = ShortArray(count)
        val colors = IntArray(count)
        val map = HashMap<Int, Int>(count * 4 / 3)

        for (i in 0 until count) {
            val hip = buf.int
            hipIds[i] = hip
            ux[i] = buf.float
            uy[i] = buf.float
            uz[i] = buf.float
            raHours[i] = buf.float
            decDegrees[i] = buf.float
            vMag[i] = buf.float
            val bvVal = buf.short.toFloat() / 1000f
            bv[i] = bvVal
            constIdx[i] = buf.short
            colors[i] = PackedStarCatalog.ballesterosArgb(bvVal.toDouble())
            if (hip > 0) map[hip] = i
        }

        return PackedStarCatalog(
            count = count,
            hipIds = hipIds,
            ux = ux,
            uy = uy,
            uz = uz,
            raHours = raHours,
            decDegrees = decDegrees,
            vMag = vMag,
            bv = bv,
            constellationIdx = constIdx,
            packedArgbColors = colors,
            indexByHip = map
        )
    }

    private fun loadStarDesignations(): Map<Int, StarDesignationRecord> {
        val list: List<StarDesignationRecord> = loadJsonAsset("cosmos/star_names_iau.json") ?: return emptyMap()
        val map = HashMap<Int, StarDesignationRecord>(list.size * 4 / 3)
        for (item in list) {
            map[item.hip] = item
        }
        return map
    }

    private fun buildBrightStarsList(
        catalog: PackedStarCatalog,
        designations: Map<Int, StarDesignationRecord>,
        constellations: List<CosmosConstellation>
    ): List<CosmosStar> {
        val constByIndex = constellations.associateBy({ it.index.toShort() }, { it.id })
        val list = ArrayList<CosmosStar>(600)
        for (i in 0 until catalog.count) {
            val hip = catalog.hipIds[i]
            val desig = designations[hip]
            val mag = catalog.vMag[i].toDouble()
            val hasProperName = !desig?.name.isNullOrBlank()
            if (hasProperName || mag <= 3.0) {
                val constCode = desig?.constellation?.uppercase()
                    ?: constByIndex[catalog.constellationIdx[i]]
                    ?: "SKY"
                val label = if (hasProperName) desig!!.name!! else (desig?.primaryLabel ?: "HIP $hip")
                list.add(
                    CosmosStar(
                        hip = hip,
                        name = label,
                        bayer = desig?.bayer?.takeIf { !it.contains("undefined") },
                        constellation = constCode,
                        raHours = catalog.raHours[i].toDouble(),
                        decDegrees = catalog.decDegrees[i].toDouble(),
                        mag = mag,
                        colorIndexBV = catalog.bv[i].toDouble()
                    )
                )
            }
        }
        list.sortBy { it.mag }
        return list
    }

    @Serializable
    private data class RawMilkyWayLayer(
        val level: Int,
        val rings: List<List<List<Double>>>
    )

    private fun loadMilkyWayIsophotes(): List<MilkyWayContourLayer> {
        val rawLayers: List<RawMilkyWayLayer> = loadJsonAsset("cosmos/milky_way_isophotes.json") ?: return emptyList()
        return rawLayers.map { layer ->
            val ringsUx = Array(layer.rings.size) { FloatArray(0) }
            val ringsUy = Array(layer.rings.size) { FloatArray(0) }
            val ringsUz = Array(layer.rings.size) { FloatArray(0) }
            layer.rings.forEachIndexed { rIdx, ring ->
                val n = ring.size
                val ux = FloatArray(n)
                val uy = FloatArray(n)
                val uz = FloatArray(n)
                for (pIdx in 0 until n) {
                    val pt = ring[pIdx]
                    if (pt.size >= 2) {
                        val raRad = Math.toRadians(pt[0] * 15.0)
                        val decRad = Math.toRadians(pt[1])
                        ux[pIdx] = (cos(decRad) * cos(raRad)).toFloat()
                        uy[pIdx] = (cos(decRad) * sin(raRad)).toFloat()
                        uz[pIdx] = sin(decRad).toFloat()
                    }
                }
                ringsUx[rIdx] = ux
                ringsUy[rIdx] = uy
                ringsUz[rIdx] = uz
            }
            MilkyWayContourLayer(layer.level, ringsUx, ringsUy, ringsUz)
        }
    }
}
