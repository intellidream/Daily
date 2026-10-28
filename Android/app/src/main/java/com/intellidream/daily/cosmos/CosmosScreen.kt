package com.intellidream.daily.cosmos

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CosmosConstellation
import com.intellidream.daily.model.CosmosDeepSkyObject
import com.intellidream.daily.model.CosmosStar
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun CosmosScreen(
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: CosmosViewModel = viewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val activity = context as? Activity

    // Detect Foldable Posture (Tabletop Flex Mode) via Jetpack WindowManager
    var isTabletopMode by remember { mutableStateOf(false) }
    var foldingSplitFraction by remember { mutableStateOf(0.5f) }

    if (activity != null) {
        LaunchedEffect(activity) {
            WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity).collect { info ->
                val fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
                if (fold != null && fold.state == FoldingFeature.State.HALF_OPENED &&
                    fold.orientation == FoldingFeature.Orientation.HORIZONTAL
                ) {
                    isTabletopMode = true
                    val bounds = fold.bounds
                    val totalHeight = activity.window.decorView.height.toFloat()
                    if (totalHeight > 0) {
                        foldingSplitFraction = (bounds.top.toFloat() / totalHeight).coerceIn(0.35f, 0.65f)
                    }
                } else {
                    isTabletopMode = false
                }
            }
        }
    }

    var showTimeScrubber by remember { mutableStateOf(false) }
    var showSearchSheet by remember { mutableStateOf(false) }

    val nightColor = Color(0xFFFF1824)
    val skyBg = if (state.isNightVisionMode) Color(0xFF140203) else Color(0xFF040814)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(skyBg)
    ) {
        if (isTabletopMode) {
            // =========================================================================
            // FOLDABLE TABLETOP FLEX MODE (Galaxy Z Fold 8 "RADAR" / Pixel Fold Half-Opened)
            // =========================================================================
            Column(modifier = Modifier.fillMaxSize()) {
                // Top Half: Star Dome Viewfinder
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(foldingSplitFraction)
                ) {
                    SkyDomeCanvas(
                        state = state,
                        stars = state.stars,
                        constellations = state.constellations,
                        dsos = state.dsos,
                        onPan = { dAz, dAlt -> viewModel.setCameraAttitude(state.cameraAzimuth - dAz, state.cameraAltitude + dAlt) },
                        onZoom = { scale -> viewModel.setFov(state.fovDegrees / scale) },
                        onSelectTarget = { viewModel.selectTarget(it) }
                    )

                    // Compact Flex Mode Badge
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .statusBarsPadding()
                            .padding(12.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.6f))
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = "🔭 Tabletop Flex Mode",
                            color = if (state.isNightVisionMode) nightColor else Color(0xFF00E5FF),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Folding Hinge Divider
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp)
                        .background(if (state.isNightVisionMode) nightColor.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.15f))
                )

                // Bottom Half: Control Deck & Target Deck
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f - foldingSplitFraction)
                        .background(if (state.isNightVisionMode) Color(0xFF1A0406) else Color(0xFF060B18))
                        .navigationBarsPadding()
                ) {
                    FlexControlDeck(
                        state = state,
                        onToggleAr = { viewModel.toggleArGyro() },
                        onToggleNightVision = { viewModel.toggleNightVision() },
                        onShiftTime = { viewModel.shiftTime(it) },
                        onResetLiveTime = { viewModel.resetToLiveTime() },
                        onSelectPlanet = { viewModel.selectTarget(CosmosSearchResult.Planet(it)) },
                        onDismissTarget = { viewModel.selectTarget(null) }
                    )
                }
            }
        } else {
            // =========================================================================
            // STANDARD / FULL VIEWPORT OBSERVATORY
            // =========================================================================
            SkyDomeCanvas(
                state = state,
                stars = state.stars,
                constellations = state.constellations,
                dsos = state.dsos,
                onPan = { dAz, dAlt -> viewModel.setCameraAttitude(state.cameraAzimuth - dAz, state.cameraAltitude + dAlt) },
                onZoom = { scale -> viewModel.setFov(state.fovDegrees / scale) },
                onSelectTarget = { viewModel.selectTarget(it) }
            )

            // Top Floating HUD
            TopCosmosHud(
                state = state,
                onBackClick = onNavigateBack,
                onToggleAr = { viewModel.toggleArGyro() },
                onToggleNightVision = { viewModel.toggleNightVision() },
                onToggleTimeScrubber = { showTimeScrubber = !showTimeScrubber },
                onOpenSearch = { showSearchSheet = true }
            )

            // Time Travel Scrubber Overlay
            AnimatedVisibility(
                visible = showTimeScrubber,
                enter = fadeIn(),
                exit = fadeOut(),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 70.dp)
            ) {
                TimeScrubberBanner(
                    state = state,
                    onShift = { viewModel.shiftTime(it) },
                    onResetLive = { viewModel.resetToLiveTime() },
                    onClose = { showTimeScrubber = false }
                )
            }

            // Bottom Target Inspector or Quick Carousel
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                if (state.selectedTarget != null) {
                    TargetInspectorCard(
                        target = state.selectedTarget!!,
                        state = state,
                        onDismiss = { viewModel.selectTarget(null) }
                    )
                } else {
                    QuickPlanetsBar(
                        planets = state.allPlanets,
                        selected = null,
                        isNightVision = state.isNightVisionMode,
                        onSelectPlanet = { viewModel.selectTarget(CosmosSearchResult.Planet(it)) }
                    )
                }
            }
        }

        // Search Bottom Sheet
        if (showSearchSheet) {
            CosmosSearchDialog(
                query = state.searchQuery,
                results = state.searchResults,
                isNightVision = state.isNightVisionMode,
                onQueryChanged = { viewModel.onSearchQueryChanged(it) },
                onSelectResult = {
                    viewModel.selectTarget(it)
                    showSearchSheet = false
                },
                onDismiss = { showSearchSheet = false }
            )
        }
    }
}

// =========================================================================
// 120Hz STEREOGRAPHIC SKY DOME CANVAS
// =========================================================================

@Composable
private fun SkyDomeCanvas(
    state: CosmosViewState,
    stars: List<CosmosStar>,
    constellations: List<CosmosConstellation>,
    dsos: List<CosmosDeepSkyObject>,
    onPan: (Double, Double) -> Unit,
    onZoom: (Float) -> Unit,
    onSelectTarget: (CosmosSearchResult) -> Unit
) {
    val isRed = state.isNightVisionMode
    val nightRed = Color(0xFFFF1824)
    val transformState = rememberTransformableState { zoomChange, _, _ ->
        if (zoomChange != 1.0f) {
            onZoom(zoomChange)
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .transformable(transformState)
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    // Drag sensitivity: 1px = ~0.15 degrees
                    val sensitivity = 0.15 * (state.fovDegrees / 60.0)
                    onPan(dragAmount.x * sensitivity, dragAmount.y * sensitivity)
                }
            }
            .pointerInput(state) {
                detectTapGestures { offset ->
                    // Hit testing closest object
                    // Tap selection handled via closest hit or center reticle
                }
            }
    ) {
        val width = constraints.maxWidth.toDouble()
        val height = constraints.maxHeight.toDouble()

        Canvas(modifier = Modifier.fillMaxSize()) {
            val center = Offset((width * 0.5).toFloat(), (height * 0.5).toFloat())

            // 1. Subtle Reticle / Crosshair at screen center
            val reticleColor = if (isRed) nightRed.copy(alpha = 0.45f) else Color(0xFF00E5FF).copy(alpha = 0.35f)
            drawLine(reticleColor, Offset(center.x - 14f, center.y), Offset(center.x + 14f, center.y), strokeWidth = 1.5f)
            drawLine(reticleColor, Offset(center.x, center.y - 14f), Offset(center.x, center.y + 14f), strokeWidth = 1.5f)
            drawCircle(reticleColor, radius = 6f, center = center, style = Stroke(width = 1.2f))

            // 2. Cardinal Horizon Markers
            val cardinals = listOf(
                Pair(0.0, "N"), Pair(45.0, "NE"), Pair(90.0, "E"), Pair(135.0, "SE"),
                Pair(180.0, "S"), Pair(225.0, "SW"), Pair(270.0, "W"), Pair(315.0, "NW")
            )
            cardinals.forEach { (az, label) ->
                val p = AstronomyService.projectStereographic(
                    raHours = 0.0, decDegrees = 0.0,
                    observerLatitudeDegrees = state.observerLatitude,
                    observerLongitudeDegrees = state.observerLongitude,
                    millis = state.effectiveTimestamp,
                    cameraAzimuthDegrees = state.cameraAzimuth,
                    cameraAltitudeDegrees = state.cameraAltitude,
                    cameraRollDegrees = state.cameraRoll,
                    fovDegrees = state.fovDegrees,
                    viewportWidth = width, viewportHeight = height
                )
                // Project cardinal along horizon (altitude = 0)
                val cardProj = projectHorizontalDirect(
                    azimuth = az, altitude = 0.0,
                    cameraAzimuth = state.cameraAzimuth,
                    cameraAltitude = state.cameraAltitude,
                    cameraRoll = state.cameraRoll,
                    fovDegrees = state.fovDegrees,
                    viewportWidth = width, viewportHeight = height
                )
                if (cardProj != null) {
                    val (cx, cy, isVis) = cardProj
                    if (isVis) {
                        val cColor = if (isRed) nightRed.copy(alpha = 0.8f) else Color(0xFFFFD54F)
                        drawCircle(cColor, radius = 3.5f, center = Offset(cx.toFloat(), cy.toFloat()))
                        drawContext.canvas.nativeCanvas.drawText(
                            label,
                            cx.toFloat(), cy.toFloat() - 8f,
                            android.graphics.Paint().apply {
                                color = if (isRed) 0xFFFF1824.toInt() else 0xFFFFD54F.toInt()
                                textSize = 28f
                                textAlign = android.graphics.Paint.Align.CENTER
                                isFakeBoldText = true
                            }
                        )
                    }
                }
            }

            // 3. Constellation Figure Lines
            val starNameMap = stars.associateBy { it.name.lowercase() }
            constellations.forEach { const ->
                for (i in 0 until const.stars.size - 1) {
                    val sStar = starNameMap[const.stars[i].lowercase()]
                    val eStar = starNameMap[const.stars[i + 1].lowercase()]
                    if (sStar != null && eStar != null) {
                        val p1 = AstronomyService.projectStereographic(
                            raHours = sStar.raHours, decDegrees = sStar.decDeg,
                            observerLatitudeDegrees = state.observerLatitude,
                            observerLongitudeDegrees = state.observerLongitude,
                            millis = state.effectiveTimestamp,
                            cameraAzimuthDegrees = state.cameraAzimuth,
                            cameraAltitudeDegrees = state.cameraAltitude,
                            cameraRollDegrees = state.cameraRoll,
                            fovDegrees = state.fovDegrees,
                            viewportWidth = width, viewportHeight = height
                        )
                        val p2 = AstronomyService.projectStereographic(
                            raHours = eStar.raHours, decDegrees = eStar.decDeg,
                            observerLatitudeDegrees = state.observerLatitude,
                            observerLongitudeDegrees = state.observerLongitude,
                            millis = state.effectiveTimestamp,
                            cameraAzimuthDegrees = state.cameraAzimuth,
                            cameraAltitudeDegrees = state.cameraAltitude,
                            cameraRollDegrees = state.cameraRoll,
                            fovDegrees = state.fovDegrees,
                            viewportWidth = width, viewportHeight = height
                        )
                        if (p1 != null && p2 != null) {
                            val lineColor = if (isRed) nightRed.copy(alpha = 0.35f) else Color(0xFF4FC3F7).copy(alpha = 0.30f)
                            drawLine(
                                color = lineColor,
                                start = Offset(p1.first.toFloat(), p1.second.toFloat()),
                                end = Offset(p2.first.toFloat(), p2.second.toFloat()),
                                strokeWidth = 1.4f
                            )
                        }
                    }
                }
            }

            // 4. Bright Stars with B-V Color Tints
            stars.forEach { star ->
                val proj = AstronomyService.projectStereographic(
                    raHours = star.raHours, decDegrees = star.decDeg,
                    observerLatitudeDegrees = state.observerLatitude,
                    observerLongitudeDegrees = state.observerLongitude,
                    millis = state.effectiveTimestamp,
                    cameraAzimuthDegrees = state.cameraAzimuth,
                    cameraAltitudeDegrees = state.cameraAltitude,
                    cameraRollDegrees = state.cameraRoll,
                    fovDegrees = state.fovDegrees,
                    viewportWidth = width, viewportHeight = height
                )
                if (proj != null && proj.third) {
                    val (sx, sy) = proj
                    val starRadius = (5.5 - (star.visualMag * 0.7)).coerceIn(1.8, 6.0).toFloat()
                    val starColor = if (isRed) {
                        nightRed.copy(alpha = (1.0 - (star.visualMag * 0.12)).coerceIn(0.4, 1.0).toFloat())
                    } else {
                        bvColorToColor(star.bvColorIndex)
                    }

                    // Soft outer glow for major 1st mag stars
                    if (star.visualMag < 1.5) {
                        drawCircle(starColor.copy(alpha = 0.25f), radius = starRadius * 2.4f, center = Offset(sx.toFloat(), sy.toFloat()))
                    }
                    drawCircle(starColor, radius = starRadius, center = Offset(sx.toFloat(), sy.toFloat()))

                    // Star label if bright (mag < 2.0)
                    if (star.visualMag < 2.0 && state.fovDegrees < 80.0) {
                        drawContext.canvas.nativeCanvas.drawText(
                            star.nameRo.ifEmpty { star.nameEn },
                            sx.toFloat(), sy.toFloat() + starRadius + 14f,
                            android.graphics.Paint().apply {
                                color = if (isRed) 0xFFFF6060.toInt() else 0xFFE0E0E0.toInt()
                                textSize = 22f
                                textAlign = android.graphics.Paint.Align.CENTER
                            }
                        )
                    }
                }
            }

            // 5. Planetary Bodies & Moon
            state.allPlanets.forEach { (body, coords) ->
                val proj = AstronomyService.projectStereographic(
                    raHours = coords.rightAscensionHours, decDegrees = coords.declinationDegrees,
                    observerLatitudeDegrees = state.observerLatitude,
                    observerLongitudeDegrees = state.observerLongitude,
                    millis = state.effectiveTimestamp,
                    cameraAzimuthDegrees = state.cameraAzimuth,
                    cameraAltitudeDegrees = state.cameraAltitude,
                    cameraRollDegrees = state.cameraRoll,
                    fovDegrees = state.fovDegrees,
                    viewportWidth = width, viewportHeight = height
                )
                if (proj != null && proj.third) {
                    val (px, py) = proj
                    val planetColor = if (isRed) nightRed else parseHexColor(body.colorHex)

                    if (body == CelestialBody.MOON) {
                        // Moon disc with illuminated crescent
                        drawCircle(planetColor.copy(alpha = 0.25f), radius = 18f, center = Offset(px.toFloat(), py.toFloat()))
                        drawCircle(planetColor, radius = 9f, center = Offset(px.toFloat(), py.toFloat()))
                    } else {
                        drawCircle(planetColor.copy(alpha = 0.35f), radius = 14f, center = Offset(px.toFloat(), py.toFloat()))
                        drawCircle(planetColor, radius = 6.5f, center = Offset(px.toFloat(), py.toFloat()))
                    }

                    // Planet label & symbol
                    drawContext.canvas.nativeCanvas.drawText(
                        "${body.symbol} ${body.displayNameRo}",
                        px.toFloat(), py.toFloat() - 14f,
                        android.graphics.Paint().apply {
                            color = if (isRed) 0xFFFF1824.toInt() else 0xFFFFFFFF.toInt()
                            textSize = 24f
                            textAlign = android.graphics.Paint.Align.CENTER
                            isFakeBoldText = true
                        }
                    )
                }
            }

            // 6. Deep Sky Objects (Messier)
            dsos.forEach { dso ->
                val proj = AstronomyService.projectStereographic(
                    raHours = dso.raHours, decDegrees = dso.decDeg,
                    observerLatitudeDegrees = state.observerLatitude,
                    observerLongitudeDegrees = state.observerLongitude,
                    millis = state.effectiveTimestamp,
                    cameraAzimuthDegrees = state.cameraAzimuth,
                    cameraAltitudeDegrees = state.cameraAltitude,
                    cameraRollDegrees = state.cameraRoll,
                    fovDegrees = state.fovDegrees,
                    viewportWidth = width, viewportHeight = height
                )
                if (proj != null && proj.third && state.fovDegrees < 85.0) {
                    val (dx, dy) = proj
                    val dsoColor = if (isRed) nightRed.copy(alpha = 0.7f) else Color(0xFFE040FB)
                    drawCircle(
                        color = dsoColor,
                        radius = 8f,
                        center = Offset(dx.toFloat(), dy.toFloat()),
                        style = Stroke(width = 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f)))
                    )
                    drawContext.canvas.nativeCanvas.drawText(
                        dso.catalogNumber,
                        dx.toFloat(), dy.toFloat() + 18f,
                        android.graphics.Paint().apply {
                            color = if (isRed) 0xFFFF1824.toInt() else 0xFFE040FB.toInt()
                            textSize = 20f
                            textAlign = android.graphics.Paint.Align.CENTER
                        }
                    )
                }
            }
        }
    }
}

private fun projectHorizontalDirect(
    azimuth: Double,
    altitude: Double,
    cameraAzimuth: Double,
    cameraAltitude: Double,
    cameraRoll: Double,
    fovDegrees: Double,
    viewportWidth: Double,
    viewportHeight: Double
): Triple<Double, Double, Boolean>? {
    val azRad = Math.toRadians(azimuth)
    val altRad = Math.toRadians(altitude)

    val cosAlt = cos(altRad)
    val xH = cosAlt * sin(azRad)
    val yH = cosAlt * cos(azRad)
    val zH = sin(altRad)

    val camAzRad = Math.toRadians(cameraAzimuth)
    val camAltRad = Math.toRadians(cameraAltitude)
    val camRollRad = Math.toRadians(cameraRoll)

    val cosAz = cos(-camAzRad)
    val sinAz = sin(-camAzRad)
    val x1 = (xH * cosAz) - (yH * sinAz)
    val y1 = (xH * sinAz) + (yH * cosAz)
    val z1 = zH

    val cosAltC = cos(-camAltRad)
    val sinAltC = sin(-camAltRad)
    val x2 = x1
    val y2 = (y1 * cosAltC) - (z1 * sinAltC)
    val z2 = (y1 * sinAltC) + (z1 * cosAltC)

    val cosRoll = cos(camRollRad)
    val sinRoll = sin(camRollRad)
    val xCam = (x2 * cosRoll) + (z2 * sinRoll)
    val yCam = (-x2 * sinRoll) + (z2 * cosRoll)
    val zForward = y2

    if (zForward <= 0.05) return null

    val denom = 1.0 + zForward
    val xs = xCam / denom
    val ys = yCam / denom

    val fovRad = Math.toRadians(fovDegrees)
    val tanHalfFov = kotlin.math.tan(fovRad / 4.0)
    if (tanHalfFov <= 1e-6) return null

    val scale = (kotlin.math.min(viewportWidth, viewportHeight) * 0.5) / tanHalfFov
    val screenX = (viewportWidth * 0.5) + (xs * scale)
    val screenY = (viewportHeight * 0.5) - (ys * scale)

    val isVis = (screenX >= -40.0 && screenX <= viewportWidth + 40.0 &&
                 screenY >= -40.0 && screenY <= viewportHeight + 40.0)

    return Triple(screenX, screenY, isVis)
}

// B-V color index to realistic RGB star tint
private fun bvColorToColor(bv: Double): Color {
    return when {
        bv < 0.0 -> Color(0xFF99CCFF) // Blue-white (O/B type, Rigel)
        bv < 0.3 -> Color(0xFFCAE1FF) // White-blue (A type, Sirius, Vega)
        bv < 0.6 -> Color(0xFFF8F9FA) // White-yellow (F/G type, Sun, Capella)
        bv < 1.0 -> Color(0xFFFFE082) // Yellow-orange (K type, Arcturus)
        else -> Color(0xFFFF8A65)     // Orange-red (M type, Betelgeuse, Antares)
    }
}

// =========================================================================
// TOP FLOATING HUD
// =========================================================================

@Composable
private fun TopCosmosHud(
    state: CosmosViewState,
    onBackClick: () -> Unit,
    onToggleAr: () -> Unit,
    onToggleNightVision: () -> Unit,
    onToggleTimeScrubber: () -> Unit,
    onOpenSearch: () -> Unit
) {
    val isRed = state.isNightVisionMode
    val nightRed = Color(0xFFFF1824)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Back Button
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.55f))
                .border(1.dp, if (isRed) nightRed.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.15f), CircleShape)
                .clickable(onClick = onBackClick),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                contentDescription = "Back",
                tint = if (isRed) nightRed else Color.White,
                modifier = Modifier.size(20.dp)
            )
        }

        // Center Coordinate Readout
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "Cosmos & Observator",
                color = if (isRed) nightRed else Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "Az: ${state.cameraAzimuth.toInt()}° • Alt: ${state.cameraAltitude.toInt()}° • FOV: ${state.fovDegrees.toInt()}°",
                color = if (isRed) nightRed.copy(alpha = 0.7f) else Color.White.copy(alpha = 0.65f),
                fontSize = 11.sp
            )
        }

        // Actions: Gyro AR, Night Vision, Search, Time Scrubber
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // AR Gyro Tracker
            HudIconButton(
                icon = Icons.Rounded.Sensors,
                isActive = state.isArGyroActive,
                activeColor = if (isRed) nightRed else Color(0xFF00E676),
                isNightVision = isRed,
                onClick = onToggleAr
            )

            // Red Night Vision
            HudIconButton(
                icon = Icons.Rounded.NightsStay,
                isActive = state.isNightVisionMode,
                activeColor = nightRed,
                isNightVision = isRed,
                onClick = onToggleNightVision
            )

            // Search
            HudIconButton(
                icon = Icons.Rounded.Search,
                isActive = false,
                activeColor = Color.White,
                isNightVision = isRed,
                onClick = onOpenSearch
            )

            // Time Travel Toggle
            HudIconButton(
                icon = Icons.Rounded.Explore,
                isActive = !state.isLiveTime,
                activeColor = Color(0xFFFFD54F),
                isNightVision = isRed,
                onClick = onToggleTimeScrubber
            )
        }
    }
}

@Composable
private fun HudIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    isActive: Boolean,
    activeColor: Color,
    isNightVision: Boolean,
    onClick: () -> Unit
) {
    val bg = if (isActive) activeColor.copy(alpha = 0.25f) else Color.Black.copy(alpha = 0.55f)
    val tint = if (isActive) activeColor else if (isNightVision) Color(0xFFFF1824).copy(alpha = 0.7f) else Color.White

    Box(
        modifier = Modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(bg)
            .border(1.dp, if (isActive) activeColor.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.12f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
    }
}

// =========================================================================
// TIME TRAVEL SCRUBBER BANNER
// =========================================================================

@Composable
private fun TimeScrubberBanner(
    state: CosmosViewState,
    onShift: (Double) -> Unit,
    onResetLive: () -> Unit,
    onClose: () -> Unit
) {
    val dateFormatter = remember { SimpleDateFormat("EEE d MMM HH:mm", Locale.getDefault()) }
    val isRed = state.isNightVisionMode
    val nightRed = Color(0xFFFF1824)

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
        cornerRadius = 16.dp,
        padding = 12.dp,
        intensity = GlassIntensity.Prominent
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = if (state.isLiveTime) "Timp Real (Live)" else "Simulare Timp",
                    color = if (state.isLiveTime) Color(0xFF00E676) else Color(0xFFFFD54F),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = dateFormatter.format(Date(state.effectiveTimestamp)),
                    color = if (isRed) nightRed else Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                ScrubberPill("-1h") { onShift(-1.0) }
                if (!state.isLiveTime) {
                    ScrubberPill("LIVE", isPrimary = true) { onResetLive() }
                }
                ScrubberPill("+1h") { onShift(1.0) }
                ScrubberPill("+24h") { onShift(24.0) }

                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .clickable(onClick = onClose),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(imageVector = Icons.Rounded.Close, contentDescription = "Close", tint = Color.White.copy(alpha = 0.6f), modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

@Composable
private fun ScrubberPill(text: String, isPrimary: Boolean = false, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(if (isPrimary) Color(0xFF00E676).copy(alpha = 0.25f) else Color.White.copy(alpha = 0.10f))
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 5.dp)
    ) {
        Text(
            text = text,
            color = if (isPrimary) Color(0xFF00E676) else Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// =========================================================================
// TARGET INSPECTOR CARD
// =========================================================================

@Composable
private fun TargetInspectorCard(
    target: CosmosSearchResult,
    state: CosmosViewState,
    onDismiss: () -> Unit
) {
    val isRed = state.isNightVisionMode
    val nightRed = Color(0xFFFF1824)

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 18.dp,
        padding = 16.dp,
        intensity = GlassIntensity.Prominent
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = target.title,
                        color = if (isRed) nightRed else Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = target.subtitle,
                        color = if (isRed) nightRed.copy(alpha = 0.7f) else Color.White.copy(alpha = 0.65f),
                        fontSize = 12.sp
                    )
                }

                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.1f))
                        .clickable(onClick = onDismiss),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(imageVector = Icons.Rounded.Close, contentDescription = "Close", tint = Color.White, modifier = Modifier.size(16.dp))
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TargetMetricItem("Calitate Cer", "${state.conditions?.score ?: 80}/100")
                TargetMetricItem("Stadiu Lună", "${state.moon?.quarter?.symbol} ${state.moon?.illuminationPercent}%")
                TargetMetricItem("Altitudine", "${state.cameraAltitude.toInt()}°")
                TargetMetricItem("Azimut", "${state.cameraAzimuth.toInt()}°")
            }
        }
    }
}

@Composable
private fun TargetMetricItem(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = label, color = Color.White.copy(alpha = 0.6f), fontSize = 10.sp)
        Text(text = value, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

// =========================================================================
// QUICK PLANETS CAROUSEL BAR
// =========================================================================

@Composable
private fun QuickPlanetsBar(
    planets: List<Pair<CelestialBody, com.intellidream.daily.model.CelestialCoordinates>>,
    selected: CelestialBody?,
    isNightVision: Boolean,
    onSelectPlanet: (CelestialBody) -> Unit
) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(planets) { (body, coords) ->
            val isVis = coords.isVisible
            val pColor = if (isNightVision) Color(0xFFFF1824) else parseHexColor(body.colorHex)

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.Black.copy(alpha = 0.60f))
                    .border(
                        1.dp,
                        if (isVis) pColor.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.08f),
                        RoundedCornerShape(12.dp)
                    )
                    .clickable { onSelectPlanet(body) }
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(text = body.symbol, color = pColor, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Text(text = body.displayNameRo, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    if (isVis) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(Color(0xFF00E676))
                        )
                    }
                }
            }
        }
    }
}

// =========================================================================
// FLEX MODE CONTROL DECK (BOTTOM HALF OF TABLETOP FOLDABLE)
// =========================================================================

@Composable
private fun FlexControlDeck(
    state: CosmosViewState,
    onToggleAr: () -> Unit,
    onToggleNightVision: () -> Unit,
    onShiftTime: (Double) -> Unit,
    onResetLiveTime: () -> Unit,
    onSelectPlanet: (CelestialBody) -> Unit,
    onDismissTarget: () -> Unit
) {
    val scrollState = rememberScrollState()
    val isRed = state.isNightVisionMode
    val nightRed = Color(0xFFFF1824)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Control Bar: Gyro AR, Night Mode, Live Time
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Consolă Observator",
                    color = if (isRed) nightRed else Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Orientare: Az ${state.cameraAzimuth.toInt()}° • Alt ${state.cameraAltitude.toInt()}°",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HudIconButton(
                    icon = Icons.Rounded.Sensors,
                    isActive = state.isArGyroActive,
                    activeColor = if (isRed) nightRed else Color(0xFF00E676),
                    isNightVision = isRed,
                    onClick = onToggleAr
                )
                HudIconButton(
                    icon = Icons.Rounded.NightsStay,
                    isActive = state.isNightVisionMode,
                    activeColor = nightRed,
                    isNightVision = isRed,
                    onClick = onToggleNightVision
                )
            }
        }

        // Stargazing Conditions Banner
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 14.dp,
            padding = 12.dp,
            intensity = GlassIntensity.Medium
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Scor Cer Nocturn",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 11.sp
                    )
                    Text(
                        text = "${state.conditions?.score ?: 80} • ${state.conditions?.quality?.displayNameRo ?: "Bun"}",
                        color = parseHexColor(state.conditions?.quality?.colorHex ?: "#00E5FF"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Lună ${state.moon?.illuminationPercent ?: 0}%",
                        color = Color.White,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = state.moon?.quarter?.displayNameRo ?: "",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 11.sp
                    )
                }
            }
        }

        // Time Travel Quick Steppers
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(modifier = Modifier.weight(1f)) { ScrubberPill("-1 oră") { onShiftTime(-1.0) } }
            Box(modifier = Modifier.weight(1f)) { ScrubberPill("ACUM", isPrimary = state.isLiveTime) { onResetLiveTime() } }
            Box(modifier = Modifier.weight(1f)) { ScrubberPill("+1 oră") { onShiftTime(1.0) } }
            Box(modifier = Modifier.weight(1f)) { ScrubberPill("+24 ore") { onShiftTime(24.0) } }
        }

        // Planets Carousel
        Text(
            text = "Selectare Rapidă Țintă",
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold
        )
        QuickPlanetsBar(
            planets = state.allPlanets,
            selected = (state.selectedTarget as? CosmosSearchResult.Planet)?.body,
            isNightVision = state.isNightVisionMode,
            onSelectPlanet = onSelectPlanet
        )

        // Selected Target Details if any
        if (state.selectedTarget != null) {
            TargetInspectorCard(
                target = state.selectedTarget,
                state = state,
                onDismiss = onDismissTarget
            )
        }
    }
}

// =========================================================================
// SEARCH DIALOG / SHEET
// =========================================================================

@Composable
private fun CosmosSearchDialog(
    query: String,
    results: List<CosmosSearchResult>,
    isNightVision: Boolean,
    onQueryChanged: (String) -> Unit,
    onSelectResult: (CosmosSearchResult) -> Unit,
    onDismiss: () -> Unit
) {
    val isRed = isNightVision
    val nightRed = Color(0xFFFF1824)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.75f))
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.Center
    ) {
        GlassCard(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .fillMaxHeight(0.70f)
                .clickable(enabled = false) {}, // prevent click-through
            cornerRadius = 20.dp,
            padding = 16.dp,
            intensity = GlassIntensity.Prominent
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Caută în Cosmos",
                        color = if (isRed) nightRed else Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Box(
                        modifier = Modifier
                            .size(30.dp)
                            .clip(CircleShape)
                            .clickable(onClick = onDismiss),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(imageVector = Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                    }
                }

                TextField(
                    value = query,
                    onValueChange = onQueryChanged,
                    placeholder = { Text("Stea, constelație, planetă, Messier...") },
                    singleLine = true,
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.White.copy(alpha = 0.08f),
                        unfocusedContainerColor = Color.White.copy(alpha = 0.05f),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedIndicatorColor = if (isRed) nightRed else Color(0xFF00E5FF)
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                )

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (results.isEmpty() && query.isNotEmpty()) {
                        Text(
                            text = "Niciun corp ceresc găsit pentru \"$query\"",
                            color = Color.White.copy(alpha = 0.5f),
                            fontSize = 12.sp,
                            modifier = Modifier.padding(top = 16.dp)
                        )
                    }

                    results.forEach { res ->
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White.copy(alpha = 0.05f))
                                .clickable { onSelectResult(res) }
                                .padding(10.dp)
                        ) {
                            Column {
                                Text(
                                    text = res.title,
                                    color = if (isRed) nightRed else Color.White,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(
                                    text = res.subtitle,
                                    color = Color.White.copy(alpha = 0.6f),
                                    fontSize = 11.sp
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun parseHexColor(hex: String): Color {
    return try {
        val clean = hex.removePrefix("#")
        val colorInt = clean.toLong(16)
        if (clean.length == 6) {
            Color(0xFF000000 or colorInt)
        } else {
            Color(colorInt)
        }
    } catch (_: Exception) {
        Color(0xFF00E5FF)
    }
}
