package com.intellidream.daily.designsystem

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Production-grade two-tier (Memory + Disk) image cache manager for Daily.
 * Features:
 *  - High-performance in-memory LRU cache storing downsampled Bitmaps.
 *  - Persistent on-disk cache preserving fetched images across scrolls and sessions.
 *  - Smart downsampling (inSampleSize) preventing heap exhaustion and GC scroll stutter.
 *  - Concurrent request deduplication to prevent duplicate downloads of the same URL.
 */
object DailyImageCacheManager {
    private val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
    private val memoryCacheSize = (maxMemory / 8).coerceIn(32 * 1024, 96 * 1024)

    val memoryCache = object : LruCache<String, Bitmap>(memoryCacheSize) {
        override fun sizeOf(key: String, bitmap: Bitmap): Int {
            return (bitmap.byteCount / 1024).coerceAtLeast(1)
        }
    }

    private val inFlight = ConcurrentHashMap<String, Deferred<Bitmap?>>()

    @Volatile
    private var diskCacheDir: File? = null

    fun initDiskCache(context: Context) {
        if (diskCacheDir == null) {
            synchronized(this) {
                if (diskCacheDir == null) {
                    val dir = File(context.applicationContext.cacheDir, "daily_image_disk_cache")
                    if (!dir.exists()) dir.mkdirs()
                    diskCacheDir = dir
                }
            }
        }
    }

    private fun urlKey(url: String, targetWidth: Int, targetHeight: Int): String {
        return "${url}_${targetWidth}x${targetHeight}"
    }

    private fun urlHash(url: String): String {
        return try {
            val md = MessageDigest.getInstance("SHA-256")
            val bytes = md.digest(url.toByteArray(Charsets.UTF_8))
            bytes.joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            url.hashCode().toString()
        }
    }

    fun getFromMemory(url: String, targetWidth: Int, targetHeight: Int): Bitmap? {
        val key = urlKey(url, targetWidth, targetHeight)
        return memoryCache.get(key)
    }

    suspend fun getImage(
        context: Context,
        url: String,
        targetWidth: Int = 400,
        targetHeight: Int = 400
    ): Bitmap? = withContext(Dispatchers.IO) {
        initDiskCache(context)
        val memKey = urlKey(url, targetWidth, targetHeight)

        // 1. Check Memory Cache
        memoryCache.get(memKey)?.let { return@withContext it }

        // 2. Coalesce in-flight requests for the same URL and target size (Thread-safe)
        val deferred = synchronized(inFlight) {
            inFlight[memKey] ?: async(Dispatchers.IO) {
                try {
                    // 3. Check Disk Cache
                    val hash = urlHash(url)
                    val diskFile = File(diskCacheDir, hash)
                    if (diskFile.exists() && diskFile.length() > 0) {
                        val decoded = decodeSampledBitmapFromFile(diskFile, targetWidth, targetHeight)
                        if (decoded != null) {
                            memoryCache.put(memKey, decoded)
                            return@async decoded
                        }
                    }

                    // 4. Download from Network to Disk Cache
                    val downloaded = downloadToDisk(url, diskFile)
                    if (downloaded && diskFile.exists() && diskFile.length() > 0) {
                        val decoded = decodeSampledBitmapFromFile(diskFile, targetWidth, targetHeight)
                        if (decoded != null) {
                            memoryCache.put(memKey, decoded)
                            return@async decoded
                        }
                    }
                    null
                } catch (_: Exception) {
                    null
                } finally {
                    inFlight.remove(memKey)
                }
            }.also { inFlight[memKey] = it }
        }

        deferred.await()
    }

    private fun downloadToDisk(urlString: String, targetFile: File): Boolean {
        var connection: HttpURLConnection? = null
        val tempFile = File(targetFile.parentFile, "${targetFile.name}_${java.util.UUID.randomUUID()}.tmp")
        try {
            var currentUrl = urlString
            var redirects = 0
            while (redirects < 3) {
                val url = URL(currentUrl)
                connection = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 7000
                    readTimeout = 7000
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36")
                }
                val code = connection.responseCode
                if (code in 300..399) {
                    val location = connection.getHeaderField("Location")
                    if (location != null) {
                        currentUrl = location
                        redirects++
                        connection.disconnect()
                        continue
                    }
                }
                if (code in 200..299) {
                    connection.inputStream.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    if (tempFile.exists() && tempFile.length() > 0) {
                        if (targetFile.exists()) targetFile.delete()
                        val renamed = tempFile.renameTo(targetFile)
                        if (!renamed && targetFile.exists() && targetFile.length() > 0) {
                            return true
                        }
                        return renamed
                    }
                }
                break
            }
        } catch (_: Exception) {
        } finally {
            try {
                connection?.disconnect()
            } catch (_: Exception) {}
            if (tempFile.exists()) {
                try { tempFile.delete() } catch (_: Exception) {}
            }
        }
        return false
    }

    private fun decodeSampledBitmapFromFile(file: File, reqWidth: Int, reqHeight: Int): Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(file.absolutePath, options)

            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.ARGB_8888
            BitmapFactory.decodeFile(file.absolutePath, options)
        } catch (_: Throwable) {
            null
        }
    }

    private fun calculateInSampleSize(
        options: BitmapFactory.Options,
        reqWidth: Int,
        reqHeight: Int
    ): Int {
        val (height: Int, width: Int) = options.outHeight to options.outWidth
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize.coerceAtLeast(1)
    }
}

/**
 * High-performance, stutter-free asynchronous image loader for Compose.
 * Synchronously paints in-memory cached bitmaps on frame 0 to prevent flashing
 * during fast list scrolling, and transparently pulls from disk/network.
 */
@Composable
fun DailyAsyncImage(
    url: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    targetWidth: Int = 400,
    targetHeight: Int = 400,
    placeholder: @Composable () -> Unit = {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White.copy(alpha = 0.06f))
        )
    }
) {
    val context = LocalContext.current

    // Synchronous memory check: if cached, this is populated on frame 0 with ZERO flash
    val initialBitmap = remember(url, targetWidth, targetHeight) {
        if (!url.isNullOrBlank()) {
            DailyImageCacheManager.getFromMemory(url, targetWidth, targetHeight)
        } else null
    }

    var bitmap by remember(url, targetWidth, targetHeight) {
        mutableStateOf(initialBitmap)
    }

    var isLoadedSynchronously by remember(url) {
        mutableStateOf(initialBitmap != null)
    }

    LaunchedEffect(url, targetWidth, targetHeight) {
        if (url.isNullOrBlank()) {
            bitmap = null
            return@LaunchedEffect
        }

        if (bitmap == null) {
            val loaded = DailyImageCacheManager.getImage(context, url, targetWidth, targetHeight)
            bitmap = loaded
        }
    }

    Box(modifier = modifier) {
        if (bitmap != null) {
            if (isLoadedSynchronously) {
                // Already rendered or loaded synchronously: instant drawing with zero latency
                Image(
                    bitmap = bitmap!!.asImageBitmap(),
                    contentDescription = contentDescription,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = contentScale
                )
            } else {
                // First-time network load: smooth crossfade
                Crossfade(
                    targetState = bitmap,
                    animationSpec = tween(durationMillis = 180),
                    label = "DailyAsyncImageCrossfade"
                ) { bmp ->
                    if (bmp != null) {
                        Image(
                            bitmap = bmp.asImageBitmap(),
                            contentDescription = contentDescription,
                            modifier = Modifier.fillMaxSize(),
                            contentScale = contentScale
                        )
                    } else {
                        placeholder()
                    }
                }
            }
        } else {
            placeholder()
        }
    }
}
