package com.intellidream.daily.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Resilient hardware location coordinator for Android.
 * Queries GPS and Network providers with caching and fallback,
 * performing reverse geocoding to resolve exact local municipality names.
 */
object AndroidLocationManager {

    fun hasLocationPermission(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    suspend fun getCurrentCoordinates(context: Context): Pair<Double, Double>? = withContext(Dispatchers.IO) {
        if (!hasLocationPermission(context)) return@withContext null

        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return@withContext null

        // 1. Try immediate last known location if fresh (<15 mins)
        val lastKnown = getFreshLastKnownLocation(locationManager)
        if (lastKnown != null) {
            return@withContext Pair(lastKnown.latitude, lastKnown.longitude)
        }

        // 2. Request fresh location with strict 8-second timeout
        val freshLocation = withTimeoutOrNull(8000L) {
            requestFreshLocation(context, locationManager)
        }

        if (freshLocation != null) {
            Pair(freshLocation.latitude, freshLocation.longitude)
        } else {
            // Fallback to any last known location
            val anyLast = getAnyLastKnownLocation(locationManager)
            if (anyLast != null) Pair(anyLast.latitude, anyLast.longitude) else null
        }
    }

    private fun getFreshLastKnownLocation(locationManager: LocationManager): Location? {
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        val now = System.currentTimeMillis()
        val maxAgeMs = 15 * 60 * 1000L // 15 mins

        return providers.mapNotNull { provider ->
            try {
                if (locationManager.isProviderEnabled(provider)) {
                    locationManager.getLastKnownLocation(provider)
                } else null
            } catch (_: SecurityException) {
                null
            }
        }.filter { (now - it.time) < maxAgeMs }
            .maxByOrNull { it.time }
    }

    private fun getAnyLastKnownLocation(locationManager: LocationManager): Location? {
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        return providers.mapNotNull { provider ->
            try {
                if (locationManager.isProviderEnabled(provider)) {
                    locationManager.getLastKnownLocation(provider)
                } else null
            } catch (_: SecurityException) {
                null
            }
        }.maxByOrNull { it.time }
    }

    @Suppress("DEPRECATION")
    private suspend fun requestFreshLocation(
        context: Context,
        locationManager: LocationManager
    ): Location? = suspendCancellableCoroutine { continuation ->
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val provider = when {
                    locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
                    locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
                    else -> LocationManager.PASSIVE_PROVIDER
                }
                val cancellationSignal = CancellationSignal()
                continuation.invokeOnCancellation { cancellationSignal.cancel() }

                locationManager.getCurrentLocation(
                    provider,
                    cancellationSignal,
                    context.mainExecutor
                ) { location ->
                    if (continuation.isActive) {
                        continuation.resume(location)
                    }
                }
            } else {
                // Fallback for API < 30
                val last = getAnyLastKnownLocation(locationManager)
                continuation.resume(last)
            }
        } catch (_: SecurityException) {
            if (continuation.isActive) continuation.resume(null)
        } catch (_: Exception) {
            if (continuation.isActive) continuation.resume(null)
        }
    }

    @Suppress("DEPRECATION")
    suspend fun reverseGeocode(context: Context, latitude: Double, longitude: Double): String? = withContext(Dispatchers.IO) {
        try {
            val geocoder = Geocoder(context, Locale.getDefault())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                suspendCancellableCoroutine { continuation ->
                    geocoder.getFromLocation(latitude, longitude, 1) { addresses ->
                        val first = addresses.firstOrNull()
                        val name = first?.locality ?: first?.subAdminArea ?: first?.adminArea
                        continuation.resume(name)
                    }
                }
            } else {
                val addresses = geocoder.getFromLocation(latitude, longitude, 1)
                val first = addresses?.firstOrNull()
                first?.locality ?: first?.subAdminArea ?: first?.adminArea
            }
        } catch (_: Exception) {
            null
        }
    }
}
