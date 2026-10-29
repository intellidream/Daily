package com.intellidream.daily.cosmos

import android.app.Activity
import android.app.DatePickerDialog
import android.content.Intent
import android.graphics.Paint
import android.graphics.Typeface
import android.provider.CalendarContract
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CenterFocusStrong
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
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
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CelestialCoordinates
import com.intellidream.daily.model.SatellitePass
import com.intellidream.daily.model.SkyProjectionMatrix
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Calendar
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

// ============================================================================
// STRICT NIGHT-VISION PALETTE (#FF1824 ZERO SCOTOPIC LEAKAGE)
// ============================================================================

private data class AndroidCosmosPalette(
    val isNightVision: Boolean,
    val bgPrimary: Color,
    val bgDeck: Color,
    val cardBg: Color,
    val pillBg: Color,
    val border: Color,
    val fgPrimary: Color,
    val fgSecondary: Color,
    val fgMuted: Color,
    val accent: Color,
    val accentSecondary: Color,
    val positive: Color,
    val warning: Color,
    val primaryRed: Color = Color(0xFFFF1824)
) {
    companion object {
        fun from(isNightVision: Boolean): AndroidCosmosPalette {
            return if (isNightVision) {
                AndroidCosmosPalette(
                    isNightVision = true,
                    bgPrimary = Color(0xFF050001),
                    bgDeck = Color(0xFF0A0002),
                    cardBg = Color(0xEB120103),
                    pillBg = Color(0xD91E0205),
                    border = Color(0x59FF1824),
                    fgPrimary = Color(0xFFFF1824),
                    fgSecondary = Color(0xFFD6111B),
                    fgMuted = Color(0xFF8F0B12),
                    accent = Color(0xFFFF1824),
                    accentSecondary = Color(0xFFB80D16),
                    positive = Color(0xFFFF1824),
                    warning = Color(0xFFD9141E)
                )
            } else {
                AndroidCosmosPalette(
                    isNightVision = false,
                    bgPrimary = Color(0xFF030712),
                    bgDeck = Color(0xFF070D1D),
                    cardBg = Color(0xE00A1022),
                    pillBg = Color(0xCC111930),
                    border = Color(0x29FFFFFF),
                    fgPrimary = Color(0xFFF8FAFC),
                    fgSecondary = Color(0xFFCBD5E1),
                    fgMuted = Color(0xFF94A3B8),
                    accent = Color(0xFF00E5FF),
                    accentSecondary = Color(0xFF38BDF8),
                    positive = Color(0xFF34D399),
                    warning = Color(0xFFFBBF24)
                )
            }
        }
    }
}

private val TIME_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())
private val DATE_TIME_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy · HH:mm:ss").withZone(ZoneId.systemDefault())

private fun formatMillisShort(ms: Long?): String {
    if (ms == null) return "--:--"
    return TIME_FMT.format(Instant.ofEpochMilli(ms))
}

@Composable
fun CosmosScreen(
    onNavigateBack: () -> Unit,
    onNavigateToWeather: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    viewModel: CosmosViewModel = viewModel()
) {
    val state by viewModel.state.collectAsState()
    val palette = remember(state.isNightVisionMode) { AndroidCosmosPalette.from(state.isNightVisionMode) }
    val context = LocalContext.current
    val activity = context as? Activity
    val lifecycleOwner = LocalLifecycleOwner.current
    val view = LocalView.current
    val haptics = LocalHapticFeedback.current

    // Strict lifecycle binding: zero background battery/CPU drain when hidden
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START, Lifecycle.Event.ON_RESUME -> viewModel.onObservatoryVisible()
                Lifecycle.Event.ON_STOP -> viewModel.onObservatoryHidden()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        viewModel.onObservatoryVisible()
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            viewModel.onObservatoryHidden()
        }
    }

    // Dark / Night-Vision system bar appearance
    if (!view.isInEditMode && activity != null) {
        SideEffect {
            val window = activity.window
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
        }
    }

    // Calibrated Jetpack WindowManager Tabletop Flex Mode (window-mapped crease bounds)
    var isTabletopMode by remember { mutableStateOf(false) }
    var topCreasePx by remember { mutableStateOf(0) }
    var bottomCreasePx by remember { mutableStateOf(0) }
    var totalWindowHeightPx by remember { mutableStateOf(0) }

    if (activity != null) {
        LaunchedEffect(activity) {
            WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity).collect { info ->
                val fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
                if (fold != null &&
                    fold.state == FoldingFeature.State.HALF_OPENED &&
                    fold.orientation == FoldingFeature.Orientation.HORIZONTAL
                ) {
                    val decor = activity.window.decorView
                    val winLoc = IntArray(2)
                    decor.getLocationInWindow(winLoc)
                    val h = decor.height
                    isTabletopMode = true
                    totalWindowHeightPx = h
                    topCreasePx = (fold.bounds.top - winLoc[1]).coerceAtLeast(180)
                    bottomCreasePx = (fold.bounds.bottom - winLoc[1]).coerceAtLeast(topCreasePx + 2)
                } else {
                    isTabletopMode = false
                }
            }
        }
    }

    var showTimeScrubber by remember { mutableStateOf(false) }
    var showSearchSheet by remember { mutableStateOf(false) }
    var showLayersSheet by remember { mutableStateOf(false) }
    var showTonightsDrawer by remember { mutableStateOf(false) }

    fun openCalendarSchedule(title: String, description: String, startMs: Long, endMs: Long) {
        runCatching {
            val intent = Intent(Intent.ACTION_INSERT).apply {
                data = CalendarContract.Events.CONTENT_URI
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.Events.DESCRIPTION, description)
                putExtra(CalendarContract.Events.EVENT_LOCATION, state.locationName)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
            }
            context.startActivity(intent)
        }
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(palette.bgPrimary)
    ) {
        val isExpandedUnfolded = maxWidth >= 700.dp && !isTabletopMode
        val isSplitDeckVisible = isExpandedUnfolded && !state.isFullBleedFoldable
        val density = LocalDensity.current

        when {
            isTabletopMode && totalWindowHeightPx > 0 -> {
                // =========================================================================
                // CALIBRATED FOLDABLE TABLETOP FLEX MODE (Z Fold 8 "RADAR" Half-Opened)
                // =========================================================================
                val topHeightDp = with(density) { topCreasePx.toDp() }
                val creaseHeightDp = with(density) { max(2, bottomCreasePx - topCreasePx).toDp() }

                Column(modifier = Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(topHeightDp)
                    ) {
                        SkyDomeViewport(
                            viewModel = viewModel,
                            state = state,
                            palette = palette,
                            isTabletopUpperPanel = true,
                            onSelectTarget = { target ->
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                viewModel.selectTarget(target, centerCamera = false)
                            }
                        )

                        // Minimal Tabletop Top Strip
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .statusBarsPadding()
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            HudCircleButton(
                                icon = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                                contentDescription = "Back to Dashboard",
                                palette = palette,
                                onClick = onNavigateBack
                            )

                            CosmosLiveHeadingBadge(
                                viewModel = viewModel,
                                state = state,
                                palette = palette,
                                prefix = "Tabletop Flex"
                            )

                            HudCircleButton(
                                icon = Icons.Rounded.Search,
                                contentDescription = "Search Celestial Catalog",
                                palette = palette,
                                onClick = { showSearchSheet = true }
                            )
                        }
                    }

                    // Physical Hinge Occlusion Divider
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(creaseHeightDp)
                            .background(palette.border)
                    )

                    // Lower Flat Surface: Complete Observatory Console
                    TabletopObservatoryConsole(
                        viewModel = viewModel,
                        state = state,
                        palette = palette,
                        onOpenLayers = { showLayersSheet = true },
                        onOpenSearch = { showSearchSheet = true },
                        onSchedulePass = { pass ->
                            openCalendarSchedule(
                                title = "🛰 ISS Visible Pass (${pass.maxAltitudeDegrees.roundToInt()}° peak)",
                                description = "Appears ${pass.startCompass}, peaks at ${pass.maxAltitudeDegrees.roundToInt()}°, sets ${pass.endCompass}. Scheduled via Daily Cosmos Observatory.",
                                startMs = pass.startTimeMillis,
                                endMs = pass.endTimeMillis
                            )
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .background(palette.bgDeck)
                            .navigationBarsPadding()
                    )
                }
            }

            isSplitDeckVisible -> {
                // =========================================================================
                // FULL-SURFACE UNFOLDED OBSERVATORY SPLIT (58% Sky Dome / 42% Deck)
                // =========================================================================
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .weight(0.58f)
                            .fillMaxHeight()
                    ) {
                        InteractiveSkyPaneContent(
                            viewModel = viewModel,
                            state = state,
                            palette = palette,
                            canToggleSplit = true,
                            isSplitActive = true,
                            showTimeScrubber = showTimeScrubber,
                            onToggleTimeScrubber = { showTimeScrubber = !showTimeScrubber },
                            onNavigateBack = onNavigateBack,
                            onNavigateToWeather = onNavigateToWeather,
                            onOpenSearch = { showSearchSheet = true },
                            onOpenLayers = { showLayersSheet = true },
                            onOpenTonightDrawer = { showTonightsDrawer = true },
                            onScheduleEvent = ::openCalendarSchedule
                        )
                    }

                    Box(
                        modifier = Modifier
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(palette.border)
                    )

                    ObservatorySideDeck(
                        viewModel = viewModel,
                        state = state,
                        palette = palette,
                        onSchedulePass = { pass ->
                            openCalendarSchedule(
                                title = "🛰 ISS Visible Pass (${pass.maxAltitudeDegrees.roundToInt()}° peak)",
                                description = "Appears ${pass.startCompass}, peaks at ${pass.maxAltitudeDegrees.roundToInt()}°, sets ${pass.endCompass}.",
                                startMs = pass.startTimeMillis,
                                endMs = pass.endTimeMillis
                            )
                        },
                        modifier = Modifier
                            .weight(0.42f)
                            .fillMaxHeight()
                            .background(palette.bgDeck)
                    )
                }
            }

            else -> {
                // =========================================================================
                // FULL-BLEED PHONE / COVER SCREEN / EXPANDED FULLSCREEN OBSERVATORY
                // =========================================================================
                InteractiveSkyPaneContent(
                    viewModel = viewModel,
                    state = state,
                    palette = palette,
                    canToggleSplit = isExpandedUnfolded,
                    isSplitActive = false,
                    showTimeScrubber = showTimeScrubber,
                    onToggleTimeScrubber = { showTimeScrubber = !showTimeScrubber },
                    onNavigateBack = onNavigateBack,
                    onNavigateToWeather = onNavigateToWeather,
                    onOpenSearch = { showSearchSheet = true },
                    onOpenLayers = { showLayersSheet = true },
                    onOpenTonightDrawer = { showTonightsDrawer = true },
                    onScheduleEvent = ::openCalendarSchedule
                )
            }
        }

        // Toast / Status Banner
        AnimatedVisibility(
            visible = state.statusBannerMessage != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(top = 98.dp)
        ) {
            state.statusBannerMessage?.let { msg ->
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(palette.cardBg)
                        .border(1.dp, palette.border, CircleShape)
                        .padding(horizontal = 14.dp, vertical = 7.dp)
                ) {
                    Text(
                        text = msg,
                        color = palette.accent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }

        // Modal Overlays (Search, Sky Layers & Date Jump, Tonight's Sky Deck)
        if (showSearchSheet) {
            CosmosSearchDialog(
                query = state.searchQuery,
                results = state.searchResults,
                bookmarks = state.bookmarks,
                palette = palette,
                onQueryChanged = { viewModel.onSearchQueryChanged(it) },
                onSelectResult = {
                    viewModel.selectTarget(it, centerCamera = true)
                    showSearchSheet = false
                },
                onSelectBookmark = { bm ->
                    viewModel.selectTarget(viewModel.targetForBookmark(bm), centerCamera = true)
                    showSearchSheet = false
                },
                onDismiss = { showSearchSheet = false }
            )
        }

        if (showLayersSheet) {
            CosmosLayersAndEpochModal(
                viewModel = viewModel,
                state = state,
                palette = palette,
                onDismiss = { showLayersSheet = false }
            )
        }

        if (showTonightsDrawer) {
            CosmosTonightsBestModal(
                viewModel = viewModel,
                state = state,
                palette = palette,
                onSchedulePass = { pass ->
                    openCalendarSchedule(
                        title = "🛰 ISS Visible Pass (${pass.maxAltitudeDegrees.roundToInt()}° peak)",
                        description = "Appears ${pass.startCompass}, peaks at ${pass.maxAltitudeDegrees.roundToInt()}°, sets ${pass.endCompass}.",
                        startMs = pass.startTimeMillis,
                        endMs = pass.endTimeMillis
                    )
                },
                onDismiss = { showTonightsDrawer = false }
            )
        }
    }
}

// ============================================================================
// INTERACTIVE SKY PANE + HUD + CONTINUOUS TIME MACHINE
// ============================================================================

@Composable
private fun InteractiveSkyPaneContent(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    canToggleSplit: Boolean,
    isSplitActive: Boolean,
    showTimeScrubber: Boolean,
    onToggleTimeScrubber: () -> Unit,
    onNavigateBack: () -> Unit,
    onNavigateToWeather: (() -> Unit)?,
    onOpenSearch: () -> Unit,
    onOpenLayers: () -> Unit,
    onOpenTonightDrawer: () -> Unit,
    onScheduleEvent: (String, String, Long, Long) -> Unit
) {
    val haptics = LocalHapticFeedback.current
    val cameraState by viewModel.cameraState.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        SkyDomeViewport(
            viewModel = viewModel,
            state = state,
            palette = palette,
            isTabletopUpperPanel = false,
            onSelectTarget = { target ->
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                viewModel.selectTarget(target, centerCamera = false)
            }
        )

        // Top HUD + Semantic Zoom Preset Strip
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                HudCircleButton(
                    icon = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                    contentDescription = "Back to Dashboard",
                    palette = palette,
                    onClick = onNavigateBack
                )

                if (onNavigateToWeather != null) {
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(palette.pillBg)
                            .border(1.dp, palette.border, CircleShape)
                            .clickable { onNavigateToWeather() }
                            .padding(horizontal = 9.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(Icons.Rounded.Cloud, contentDescription = null, tint = palette.accent, modifier = Modifier.size(13.dp))
                        Text("Weather", color = palette.accent, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    }
                }

                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    CosmosLiveHeadingBadge(viewModel = viewModel, state = state, palette = palette)
                }

                // Red Night-Vision (#FF1824)
                HudCircleButton(
                    icon = Icons.Rounded.Visibility,
                    contentDescription = "Toggle Red Night-Vision Mode",
                    palette = palette,
                    isActive = state.isNightVisionMode,
                    activeTint = palette.primaryRed,
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        viewModel.toggleNightVision()
                    }
                )

                // Validated AR Gyroscope (only shown when IMU hardware exists)
                if (viewModel.motionManager.hasSensorHardware) {
                    HudCircleButton(
                        icon = Icons.Rounded.Sensors,
                        contentDescription = "Point-to-Sky AR Gyroscope",
                        palette = palette,
                        isActive = cameraState.isArGyroActive,
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            viewModel.toggleArGyro()
                        }
                    )
                }

                // Sky Layers & Epoch Modal
                HudCircleButton(
                    icon = Icons.Rounded.Layers,
                    contentDescription = "Sky Layers and Date Jump",
                    palette = palette,
                    onClick = onOpenLayers
                )

                // Search Catalog
                HudCircleButton(
                    icon = Icons.Rounded.Search,
                    contentDescription = "Search Sky Catalog",
                    palette = palette,
                    onClick = onOpenSearch
                )

                if (canToggleSplit) {
                    HudCircleButton(
                        icon = if (isSplitActive) Icons.Rounded.Fullscreen else Icons.Rounded.FullscreenExit,
                        contentDescription = if (isSplitActive) "Expand Full-Bleed Sky Dome" else "Show Observatory Split Deck",
                        palette = palette,
                        isActive = isSplitActive,
                        onClick = { viewModel.toggleFullBleedFoldable() }
                    )
                }
            }

            // Semantic FOV Presets (120° Wide / 60° Eye / 8° 7x50 / 2° Scope)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CosmosZoomPreset.entries.forEach { preset ->
                    val selected = abs(cameraState.fovDegrees - preset.fovDegrees) < max(1.6, preset.fovDegrees * 0.22)
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (selected) palette.accent else palette.pillBg)
                            .border(1.dp, palette.border, CircleShape)
                            .clickable {
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                viewModel.applyZoomPreset(preset)
                            }
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = preset.label,
                            color = if (selected) Color.Black else palette.fgSecondary,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                if (cameraState.needsCompassCalibration && cameraState.isArGyroActive) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(palette.pillBg)
                            .border(1.dp, palette.warning, CircleShape)
                            .padding(horizontal = 9.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = "Calibrate Compass (Figure-8)",
                            color = palette.warning,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                } else if (cameraState.isRelativeGyroFallback && cameraState.isArGyroActive) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(palette.pillBg)
                            .border(1.dp, palette.border, CircleShape)
                            .padding(horizontal = 9.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = "Relative Gyro Mode",
                            color = palette.fgMuted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }

        // Bottom Target Inspector + Continuous Time Machine Console
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            state.selectedTarget?.let { target ->
                TargetInspectorCard(
                    viewModel = viewModel,
                    target = target,
                    metrics = state.selectedTargetMetrics,
                    state = state,
                    palette = palette,
                    onScheduleTarget = {
                        val startMs = state.selectedTargetMetrics?.riseTransitSet?.transitMillis
                            ?: (System.currentTimeMillis() + 3_600_000L)
                        onScheduleEvent(
                            "🔭 Observe ${target.title}",
                            "${target.subtitle} — Scheduled from Daily Cosmos Observatory.",
                            startMs,
                            startMs + 2_700_000L
                        )
                    },
                    onDismiss = { viewModel.selectTarget(null) }
                )
            }

            if (showTimeScrubber) {
                ContinuousTimeMachineCard(
                    viewModel = viewModel,
                    state = state,
                    palette = palette
                )
            }

            // Bottom Observatory Capsule
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(palette.cardBg)
                    .border(1.dp, palette.border, CircleShape)
                    .padding(horizontal = 10.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(if (showTimeScrubber) palette.accent else palette.pillBg)
                        .clickable { onToggleTimeScrubber() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Schedule,
                        contentDescription = "Toggle Continuous Time Machine",
                        tint = if (showTimeScrubber) Color.Black else palette.accent,
                        modifier = Modifier.size(15.dp)
                    )
                }

                SmallPillButton("-1h", palette) { viewModel.shiftTime(-1.0) }

                val speed = state.playbackSpeedMultiplier
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(if (speed != 0) palette.accent else palette.pillBg)
                        .clickable {
                            val next = when (speed) {
                                0 -> 60
                                60 -> 600
                                else -> 0
                            }
                            viewModel.setPlaybackSpeed(if (next == 0) speed else next)
                        }
                        .padding(horizontal = 9.dp, vertical = 6.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        Icon(
                            imageVector = if (speed != 0) Icons.Rounded.FastForward else Icons.Rounded.PlayArrow,
                            contentDescription = "Cycle Sky Time-Lapse Speed",
                            tint = if (speed != 0) Color.Black else palette.fgPrimary,
                            modifier = Modifier.size(13.dp)
                        )
                        if (speed != 0) {
                            Text("${speed}×", color = Color.Black, fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(palette.pillBg)
                        .clickable { viewModel.resetToLiveTime() }
                        .padding(horizontal = 9.dp, vertical = 6.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(if (state.isLiveTime) palette.positive else palette.warning)
                        )
                        Text(
                            text = if (state.isLiveTime) "LIVE" else "NOW",
                            color = if (state.isLiveTime) palette.positive else palette.fgPrimary,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                SmallPillButton("+1h", palette) { viewModel.shiftTime(1.0) }

                Spacer(modifier = Modifier.weight(1f))

                if (!isSplitActive) {
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(palette.pillBg)
                            .border(1.dp, palette.border, CircleShape)
                            .clickable { onOpenTonightDrawer() }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = palette.accent, modifier = Modifier.size(12.dp))
                        Text(
                            text = "Tonight (${state.conditions?.score ?: "--"})",
                            color = palette.accent,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1
                        )
                    }
                }
            }
        }
    }
}

// ============================================================================
// ISOLATED HEADING BADGE (SUBSCRIBES TO 120HZ CAMERA WITHOUT REBUILDING HUD)
// ============================================================================

@Composable
private fun CosmosLiveHeadingBadge(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    prefix: String? = null
) {
    val cam by viewModel.cameraState.collectAsState()
    val azInt = ((cam.azimuthDegrees.roundToInt() % 360) + 360) % 360
    val dir = CelestialCoordinates.compassPoint(cam.azimuthDegrees)
    val altInt = cam.altitudeDegrees.roundToInt()
    val fovStr = if (cam.fovDegrees < 10.0) "${"%.1f".format(cam.fovDegrees)}°" else "${cam.fovDegrees.roundToInt()}°"

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = "${prefix ?: state.locationName} · %03d° %s · %+d° · %s".format(azInt, dir, altInt, fovStr),
            color = palette.fgPrimary,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = if (state.isLiveTime) "LIVE EPHEMERIS" else DATE_TIME_FMT.format(Instant.ofEpochMilli(state.effectiveTimestamp)),
            color = if (state.isLiveTime) palette.positive else palette.warning,
            fontSize = 9.5.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = FontFamily.Monospace,
            maxLines = 1
        )
    }
}

// ============================================================================
// 120HZ ZERO-RECOMPOSITION SKY DOME VIEWPORT & BATCH STEREOGRAPHIC RENDERER
// ============================================================================

private data class TapCandidate(
    val result: CosmosSearchResult,
    val x: Float,
    val y: Float,
    val priorityBonusPx: Float = 0f
)

@Composable
private fun SkyDomeViewport(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    isTabletopUpperPanel: Boolean,
    onSelectTarget: (CosmosSearchResult) -> Unit
) {
    val camera by viewModel.cameraState.collectAsState()
    val tapCandidatesRef = remember { ArrayList<TapCandidate>(128) }

    // Reusable native Paint objects (zero per-frame allocations inside DrawScope!)
    val labelPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 26f
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
    }
    val subPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 22f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
        }
    }

    val transformState = rememberTransformableState { zoomChange, _, _ ->
        if (zoomChange != 1.0f && zoomChange.isFinite() && zoomChange > 0f) {
            val curFov = viewModel.cameraState.value.fovDegrees
            viewModel.setFov(curFov / zoomChange.toDouble())
        }
    }

    val visiblePlanetsSummary = remember(state.visiblePlanets, state.moon, state.conditions) {
        val pNames = state.visiblePlanets.joinToString(", ") { "${it.first.displayName} (${it.second.compassDirection})" }
        val moonSummary = state.moon?.let { "${it.quarter.displayName} ${it.illuminationPercent}%" } ?: "Moon"
        "Interactive Night Sky Dome. $moonSummary. Sky score ${state.conditions?.score ?: "--"} of 100. Visible planets: ${pNames.ifBlank { "none above horizon" }}."
    }

    Canvas(
        modifier = Modifier
            .fillMaxSize()
            .semantics { contentDescription = visiblePlanetsSummary }
            .transformable(transformState)
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    val cam = viewModel.cameraState.value
                    val degPerPx = (cam.fovDegrees / max(320f, min(size.width.toFloat(), size.height.toFloat()))) * 0.92
                    viewModel.setCameraAttitude(
                        azimuth = cam.azimuthDegrees - dragAmount.x * degPerPx,
                        altitude = cam.altitudeDegrees + dragAmount.y * degPerPx
                    )
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(
                    onDoubleTap = { offset ->
                        val cam = viewModel.cameraState.value
                        val proj = AstronomyService.makeProjectionMatrix(
                            observerLatitudeDegrees = viewModel.state.value.observerLatitude,
                            observerLongitudeDegrees = viewModel.state.value.observerLongitude,
                            millis = viewModel.state.value.effectiveTimestamp,
                            cameraAzimuthDegrees = cam.azimuthDegrees,
                            cameraAltitudeDegrees = cam.altitudeDegrees,
                            cameraRollDegrees = cam.rollDegrees,
                            fovDegrees = cam.fovDegrees,
                            viewportWidth = size.width.toDouble(),
                            viewportHeight = size.height.toDouble()
                        )
                        val unproj = proj.unprojectToHorizontal(offset.x.toDouble(), offset.y.toDouble())
                        if (unproj != null) {
                            viewModel.setCameraAttitude(unproj.first, unproj.second)
                            viewModel.setFov((cam.fovDegrees * 0.65).coerceAtLeast(1.0))
                        }
                    },
                    onTap = { tapOffset ->
                        val maxHitPx = 44.dp.toPx()
                        var best: TapCandidate? = null
                        var bestScore = Float.MAX_VALUE
                        for (i in 0 until tapCandidatesRef.size) {
                            val c = tapCandidatesRef[i]
                            val d = hypot(tapOffset.x - c.x, tapOffset.y - c.y)
                            if (d <= maxHitPx) {
                                val eff = d - c.priorityBonusPx
                                if (eff < bestScore) {
                                    bestScore = eff
                                    best = c
                                }
                            }
                        }
                        if (best != null) {
                            onSelectTarget(best.result)
                        }
                    }
                )
            }
    ) {
        val w = size.width.toDouble()
        val h = size.height.toDouble()
        if (w <= 4.0 || h <= 4.0) return@Canvas

        // Apply tabletop upper-panel hinge tilt compensation when AR gyro is off
        val effectiveAlt = if (isTabletopUpperPanel && !camera.isArGyroActive && camera.hingeAngleDegrees != null) {
            val tiltFromVertical = (180.0 - camera.hingeAngleDegrees!!.toDouble()).coerceIn(15.0, 85.0)
            (camera.altitudeDegrees + tiltFromVertical * 0.15).coerceIn(-20.0, 90.0)
        } else {
            camera.altitudeDegrees
        }

        val proj = AstronomyService.makeProjectionMatrix(
            observerLatitudeDegrees = state.observerLatitude,
            observerLongitudeDegrees = state.observerLongitude,
            millis = state.effectiveTimestamp,
            cameraAzimuthDegrees = camera.azimuthDegrees,
            cameraAltitudeDegrees = effectiveAlt,
            cameraRollDegrees = camera.rollDegrees,
            fovDegrees = camera.fovDegrees,
            viewportWidth = w,
            viewportHeight = h
        )

        tapCandidatesRef.clear()

        // 1. Rayleigh Daylight / Twilight / Obsidian Sky Gradient
        drawRayleighSkyBackground(state = state, palette = palette)

        // 2. 5-Layer Milky Way Isophote Contours
        if (state.showMilkyWay && (!state.showAtmosphere || state.sunAltitudeDegrees < -4.0)) {
            drawMilkyWayContours(state = state, proj = proj, palette = palette)
        }

        // 3. Coordinate Grids (Equatorial RA/Dec, Alt-Azimuth & Ecliptic)
        if (state.showRaDecGrid) {
            drawEquatorialGrid(proj = proj, palette = palette)
        }
        if (state.showAltAzGrid) {
            drawAltAzGrid(proj = proj, palette = palette)
        }
        if (state.showEcliptic) {
            drawEclipticPlane(proj = proj, state = state, palette = palette)
        }

        // 4. Constellation Boundaries, 88 IAU Constellation Stick Figures & 14 Asterisms
        if (state.showConstellationBorders) {
            drawConstellationBorders(state = state, proj = proj, palette = palette)
        }
        if (state.showConstellationLines) {
            drawConstellations(
                state = state,
                proj = proj,
                palette = palette,
                labelPaint = labelPaint,
                candidates = tapCandidatesRef
            )
        }
        if (state.showAsterisms) {
            drawAsterisms(state = state, proj = proj, palette = palette, labelPaint = labelPaint)
        }

        // 5. All 15,544 Hipparcos Stars (`PackedStarCatalog` SoA zero-boxing batch loop)
        drawPackedStarField(
            state = state,
            proj = proj,
            fovDegrees = camera.fovDegrees,
            palette = palette,
            labelPaint = subPaint,
            candidates = tapCandidatesRef
        )

        // 6. 219 Messier + Caldwell Deep-Sky Objects
        if (state.showDeepSkyObjects) {
            drawDeepSkyCatalog(
                state = state,
                proj = proj,
                fovDegrees = camera.fovDegrees,
                palette = palette,
                labelPaint = subPaint,
                candidates = tapCandidatesRef
            )
        }

        // 7. Active IAU Meteor Shower Radiants
        if (state.showMeteorRadiants) {
            drawMeteorRadiants(
                state = state,
                proj = proj,
                palette = palette,
                labelPaint = subPaint,
                candidates = tapCandidatesRef
            )
        }

        // 8. Solar System Bodies (Spherical Moon Terminator, Saturn Rings, Jupiter + Galilean Moons, Planets, Sun)
        drawSolarSystemBodies(
            state = state,
            proj = proj,
            fovDegrees = camera.fovDegrees,
            palette = palette,
            labelPaint = labelPaint,
            subPaint = subPaint,
            candidates = tapCandidatesRef
        )

        // 9. Live SGP4 ISS Trajectory Arc (Sunlit vs Umbra) & Live Station Marker
        if (state.showSatellites) {
            drawIssSatelliteAndTrajectory(
                state = state,
                proj = proj,
                palette = palette,
                labelPaint = labelPaint,
                candidates = tapCandidatesRef
            )
        }

        // 10. Ground Horizon Silhouette & Cardinal / Intercardinal Compass Ring
        drawHorizonAndCompass(
            proj = proj,
            cameraAzimuth = camera.azimuthDegrees,
            cameraAltitude = camera.altitudeDegrees,
            palette = palette,
            labelPaint = labelPaint
        )

        // 11. Center Reticle & Off-Axis AR Target Guide Arrow
        val center = Offset(size.width * 0.5f, size.height * 0.5f)
        val retColor = palette.accent.copy(alpha = 0.36f)
        drawLine(retColor, Offset(center.x - 12f, center.y), Offset(center.x + 12f, center.y), strokeWidth = 1.4f)
        drawLine(retColor, Offset(center.x, center.y - 12f), Offset(center.x, center.y + 12f), strokeWidth = 1.4f)
        drawCircle(retColor, radius = 5.5f, center = center, style = Stroke(width = 1.2f))

        drawTargetSelectionAndGuideArrow(state = state, proj = proj, palette = palette)
    }
}

// ============================================================================
// SKY DOME LAYER RENDERING FUNCTIONS
// ============================================================================

private fun DrawScope.drawRayleighSkyBackground(
    state: CosmosViewState,
    palette: AndroidCosmosPalette
) {
    if (palette.isNightVision) {
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(Color(0xFF090002), Color(0xFF040001), Color(0xFF120103))
            )
        )
        return
    }
    if (!state.showAtmosphere) {
        drawRect(Color(0xFF02040A))
        return
    }
    val sunAlt = state.sunAltitudeDegrees
    val colors = when {
        sunAlt > 2.0 -> listOf(Color(0xFF123C73), Color(0xFF2563A6), Color(0xFF5FA4DC))
        sunAlt > -6.0 -> listOf(Color(0xFF0A1938), Color(0xFF1E3563), Color(0xFF8C4A3E))
        sunAlt > -12.0 -> listOf(Color(0xFF060E24), Color(0xFF0E1E42), Color(0xFF312A48))
        sunAlt > -18.0 -> listOf(Color(0xFF040817), Color(0xFF081128), Color(0xFF141D38))
        else -> listOf(Color(0xFF02050E), Color(0xFF050B1C), Color(0xFF0B1429))
    }
    drawRect(brush = Brush.verticalGradient(colors = colors))
}

private fun DrawScope.drawMilkyWayContours(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette
) {
    val path = Path()
    for (layer in state.milkyWayLayers) {
        val baseAlpha = (0.024f + layer.level * 0.011f).coerceAtMost(0.085f)
        val fill = if (palette.isNightVision) palette.primaryRed.copy(alpha = baseAlpha * 0.65f)
        else Color(0xFF8FB8FF).copy(alpha = baseAlpha)

        for (rIdx in layer.ringsUx.indices) {
            val rUx = layer.ringsUx[rIdx]
            val rUy = layer.ringsUy[rIdx]
            val rUz = layer.ringsUz[rIdx]
            path.reset()
            var started = false
            var prevX = 0f
            var prevY = 0f
            var visiblePts = 0
            for (i in rUx.indices) {
                val p = proj.projectEQJUnitVector(
                    rUx[i].toDouble(),
                    rUy[i].toDouble(),
                    rUz[i].toDouble(),
                    margin = 220.0
                ) ?: continue
                val sx = p.x.toFloat()
                val sy = p.y.toFloat()
                if (p.isVisible) visiblePts++
                if (!started) {
                    path.moveTo(sx, sy)
                    started = true
                } else if (hypot(sx - prevX, sy - prevY) < size.width * 0.45f) {
                    path.lineTo(sx, sy)
                } else {
                    path.moveTo(sx, sy)
                }
                prevX = sx
                prevY = sy
            }
            if (started && visiblePts >= 3) {
                path.close()
                drawPath(path, color = fill)
            }
        }
    }
}

private fun DrawScope.drawAltAzGrid(proj: SkyProjectionMatrix, palette: AndroidCosmosPalette) {
    val gridColor = palette.accent.copy(alpha = 0.14f)
    for (alt in listOf(15.0, 30.0, 45.0, 60.0, 75.0)) {
        var prev: Offset? = null
        for (azStep in 0..72) {
            val p = proj.projectHorizontal(azStep * 5.0, alt, margin = 120.0)
            if (p != null) {
                val cur = Offset(p.x.toFloat(), p.y.toFloat())
                if (prev != null && hypot(cur.x - prev.x, cur.y - prev.y) < size.width * 0.4f) {
                    drawLine(gridColor, prev, cur, strokeWidth = 1f)
                }
                prev = cur
            } else {
                prev = null
            }
        }
    }
    for (az in 0 until 360 step 30) {
        var prev: Offset? = null
        for (altStep in 0..17) {
            val p = proj.projectHorizontal(az.toDouble(), altStep * 5.0, margin = 120.0)
            if (p != null) {
                val cur = Offset(p.x.toFloat(), p.y.toFloat())
                if (prev != null && hypot(cur.x - prev.x, cur.y - prev.y) < size.width * 0.4f) {
                    drawLine(gridColor, prev, cur, strokeWidth = 1f)
                }
                prev = cur
            } else {
                prev = null
            }
        }
    }
}

private fun DrawScope.drawEquatorialGrid(proj: SkyProjectionMatrix, palette: AndroidCosmosPalette) {
    val eqColor = (if (palette.isNightVision) palette.primaryRed else Color(0xFF818CF8)).copy(alpha = 0.16f)
    for (dec in listOf(-60.0, -30.0, 0.0, 30.0, 60.0)) {
        val decRad = Math.toRadians(dec)
        val cd = cos(decRad)
        val sd = sin(decRad)
        var prev: Offset? = null
        for (raStep in 0..72) {
            val raRad = Math.toRadians(raStep * 5.0)
            val p = proj.projectEQJUnitVector(cd * cos(raRad), cd * sin(raRad), sd, margin = 120.0)
            if (p != null) {
                val cur = Offset(p.x.toFloat(), p.y.toFloat())
                if (prev != null && hypot(cur.x - prev.x, cur.y - prev.y) < size.width * 0.4f) {
                    drawLine(eqColor, prev, cur, strokeWidth = if (dec == 0.0) 1.5f else 0.9f)
                }
                prev = cur
            } else {
                prev = null
            }
        }
    }
}

private fun DrawScope.drawEclipticPlane(
    proj: SkyProjectionMatrix,
    state: CosmosViewState,
    palette: AndroidCosmosPalette
) {
    val eps = Math.toRadians(23.43929)
    val ce = cos(eps)
    val se = sin(eps)
    val eclColor = (if (palette.isNightVision) palette.primaryRed else Color(0xFFFBBF24)).copy(alpha = 0.28f)
    val dash = PathEffect.dashPathEffect(floatArrayOf(10f, 8f), 0f)
    var prev: Offset? = null
    for (lonDeg in 0..360 step 5) {
        val l = Math.toRadians(lonDeg.toDouble())
        val vx = cos(l)
        val vy = sin(l) * ce
        val vz = sin(l) * se
        val p = proj.projectEQJUnitVector(vx, vy, vz, margin = 100.0)
        if (p != null) {
            val cur = Offset(p.x.toFloat(), p.y.toFloat())
            if (prev != null && hypot(cur.x - prev.x, cur.y - prev.y) < size.width * 0.4f) {
                drawLine(eclColor, prev, cur, strokeWidth = 1.3f, pathEffect = dash)
            }
            prev = cur
        } else {
            prev = null
        }
    }
}

private fun DrawScope.drawConstellationBorders(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette
) {
    val borderColor = palette.fgMuted.copy(alpha = 0.22f)
    val dash = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f)
    for (arc in state.constellationBorders) {
        var prev: Offset? = null
        for (pt in arc.points) {
            if (pt.size < 2) continue
            val raRad = Math.toRadians(pt[0] * 15.0)
            val decRad = Math.toRadians(pt[1])
            val p = proj.projectEQJUnitVector(
                cos(decRad) * cos(raRad),
                cos(decRad) * sin(raRad),
                sin(decRad),
                margin = 100.0
            )
            if (p != null) {
                val cur = Offset(p.x.toFloat(), p.y.toFloat())
                if (prev != null && hypot(cur.x - prev.x, cur.y - prev.y) < size.width * 0.4f) {
                    drawLine(borderColor, prev, cur, strokeWidth = 1f, pathEffect = dash)
                }
                prev = cur
            } else {
                prev = null
            }
        }
    }
}

private fun DrawScope.drawConstellations(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    val stars = state.packedStars
    if (stars.count == 0) return
    val lineColor = (if (palette.isNightVision) palette.primaryRed else Color(0xFF4CC9F0)).copy(alpha = 0.34f)
    labelPaint.color = if (palette.isNightVision) 0x99FF1824.toInt() else 0x8893C5FD.toInt()
    labelPaint.textSize = 23f

    for (constellation in state.constellations) {
        var anyVisible = false
        for (seg in constellation.segments) {
            if (seg.size < 2) continue
            val idxA = stars.indexByHip[seg[0]] ?: continue
            val idxB = stars.indexByHip[seg[1]] ?: continue
            val pA = proj.projectEQJUnitVector(
                stars.ux[idxA].toDouble(), stars.uy[idxA].toDouble(), stars.uz[idxA].toDouble(), margin = 160.0
            ) ?: continue
            val pB = proj.projectEQJUnitVector(
                stars.ux[idxB].toDouble(), stars.uy[idxB].toDouble(), stars.uz[idxB].toDouble(), margin = 160.0
            ) ?: continue
            if (!pA.isVisible && !pB.isVisible) continue
            val a = Offset(pA.x.toFloat(), pA.y.toFloat())
            val b = Offset(pB.x.toFloat(), pB.y.toFloat())
            if (hypot(a.x - b.x, a.y - b.y) < size.width * 0.65f) {
                drawLine(lineColor, a, b, strokeWidth = 1.35f)
                anyVisible = true
            }
        }
        if (anyVisible) {
            val raRad = Math.toRadians(constellation.centerRaHours * 15.0)
            val decRad = Math.toRadians(constellation.centerDecDeg)
            val cp = proj.projectEQJUnitVector(
                cos(decRad) * cos(raRad), cos(decRad) * sin(raRad), sin(decRad), margin = 20.0
            )
            if (cp != null && cp.isVisible) {
                val cx = cp.x.toFloat()
                val cy = cp.y.toFloat()
                drawContext.canvas.nativeCanvas.drawText(
                    constellation.nameLa.uppercase(),
                    cx - 28f,
                    cy,
                    labelPaint
                )
                candidates.add(TapCandidate(CosmosSearchResult.Constellation(constellation), cx, cy, -6f))
            }
        }
    }
}

private fun DrawScope.drawAsterisms(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette,
    labelPaint: Paint
) {
    val stars = state.packedStars
    if (stars.count == 0) return
    val astColor = (if (palette.isNightVision) palette.primaryRed else Color(0xFFF59E0B)).copy(alpha = 0.42f)
    val dash = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)
    labelPaint.color = if (palette.isNightVision) 0xAAFF1824.toInt() else 0xAAFCBF49.toInt()
    labelPaint.textSize = 22f

    for (ast in state.asterisms) {
        var visible = false
        for (seg in ast.segments) {
            if (seg.size < 2) continue
            val idxA = stars.indexByHip[seg[0]] ?: continue
            val idxB = stars.indexByHip[seg[1]] ?: continue
            val pA = proj.projectEQJUnitVector(stars.ux[idxA].toDouble(), stars.uy[idxA].toDouble(), stars.uz[idxA].toDouble()) ?: continue
            val pB = proj.projectEQJUnitVector(stars.ux[idxB].toDouble(), stars.uy[idxB].toDouble(), stars.uz[idxB].toDouble()) ?: continue
            if (!pA.isVisible && !pB.isVisible) continue
            drawLine(astColor, Offset(pA.x.toFloat(), pA.y.toFloat()), Offset(pB.x.toFloat(), pB.y.toFloat()), strokeWidth = 1.6f, pathEffect = dash)
            visible = true
        }
        if (visible) {
            val raRad = Math.toRadians(ast.centerRaHours * 15.0)
            val decRad = Math.toRadians(ast.centerDecDeg)
            val cp = proj.projectEQJUnitVector(cos(decRad) * cos(raRad), cos(decRad) * sin(raRad), sin(decRad))
            if (cp != null && cp.isVisible) {
                drawContext.canvas.nativeCanvas.drawText(ast.name, cp.x.toFloat() - 24f, cp.y.toFloat(), labelPaint)
            }
        }
    }
}

private fun DrawScope.drawPackedStarField(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    fovDegrees: Double,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    val cat = state.packedStars
    if (cat.count == 0) return

    // Dynamic limiting magnitude scaled by FOV + daylight suppression
    val daylightPenalty = if (state.showAtmosphere && state.sunAltitudeDegrees > -4.0) {
        ((state.sunAltitudeDegrees + 4.0) * 0.55).coerceAtMost(5.2)
    } else 0.0

    val zoomGain = when {
        fovDegrees <= 4.0 -> 2.2
        fovDegrees <= 12.0 -> 1.5
        fovDegrees <= 35.0 -> 0.8
        fovDegrees <= 75.0 -> 0.2
        else -> -0.5
    }
    val baseNelm = (state.conditions?.limitingMagnitude ?: 5.8).coerceAtLeast(5.4)
    val magLimit = (baseNelm + zoomGain - daylightPenalty).coerceIn(1.5, 7.05)

    val phaseSeed = (state.effectiveTimestamp / 180L).toInt()

    for (i in 0 until cat.count) {
        val mag = cat.vMag[i].toDouble()
        if (mag > magLimit) break // Catalog is pre-sorted brightest-first!

        val vx = cat.ux[i].toDouble()
        val vy = cat.uy[i].toDouble()
        val vz = cat.uz[i].toDouble()
        val p = proj.projectEQJUnitVector(vx, vy, vz, margin = 12.0) ?: continue
        if (!p.isVisible) continue

        // Approximate sin(altitude) via third row of EQJ_HOR for atmospheric extinction & scintillation
        val sinAlt = proj.h20 * vx + proj.h21 * vy + proj.h22 * vz
        if (state.showAtmosphere && sinAlt < -0.04 && fovDegrees > 25.0) continue

        val sx = p.x.toFloat()
        val sy = p.y.toFloat()

        // Pogson perceptual radius + low-altitude airmass scintillation
        val flux = 10.0.pow(-0.18 * (mag - 1.0)).toFloat().coerceIn(0.18f, 3.4f)
        val radiusPx = (1.35f + flux * 2.15f).coerceIn(1.1f, 6.8f)
        val twinkle = if (sinAlt in 0.0..0.32) {
            val wave = sin(((i * 37 + phaseSeed) % 100) * 0.0628f)
            (1.0f - (0.32f - sinAlt.toFloat()) * 0.55f * abs(wave)).coerceIn(0.45f, 1.0f)
        } else 1.0f

        val alpha = ((1.05f - ((mag / (magLimit + 0.8)).toFloat() * 0.55f)) * twinkle).coerceIn(0.22f, 1.0f)
        val starColor = if (palette.isNightVision) {
            palette.primaryRed.copy(alpha = alpha)
        } else {
            Color(cat.packedArgbColors[i]).copy(alpha = alpha)
        }

        if (mag <= 1.6) {
            drawCircle(starColor.copy(alpha = alpha * 0.22f), radius = radiusPx * 2.8f, center = Offset(sx, sy))
        }
        drawCircle(starColor, radius = radiusPx, center = Offset(sx, sy))
    }

    // Named / Bright Star Labels & Tap Hit Targets
    val labelMagCutoff = when {
        fovDegrees <= 15.0 -> 3.6
        fovDegrees <= 45.0 -> 2.5
        else -> 1.65
    }
    labelPaint.color = if (palette.isNightVision) 0xDDFF1824.toInt() else 0xDDE2E8F0.toInt()
    labelPaint.textSize = 23f

    for (star in state.stars) {
        if (star.mag > max(labelMagCutoff, 3.2)) break
        val raRad = Math.toRadians(star.raHours * 15.0)
        val decRad = Math.toRadians(star.decDegrees)
        val p = proj.projectEQJUnitVector(cos(decRad) * cos(raRad), cos(decRad) * sin(raRad), sin(decRad)) ?: continue
        if (!p.isVisible) continue
        val sx = p.x.toFloat()
        val sy = p.y.toFloat()
        candidates.add(TapCandidate(CosmosSearchResult.Star(star), sx, sy, 4f))
        if (star.mag <= labelMagCutoff && (!state.showAtmosphere || state.sunAltitudeDegrees < -2.0)) {
            drawContext.canvas.nativeCanvas.drawText(star.name, sx + 8f, sy - 6f, labelPaint)
        }
    }
}

private fun DrawScope.drawDeepSkyCatalog(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    fovDegrees: Double,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    val maxDsoMag = when {
        fovDegrees <= 6.0 -> 12.5
        fovDegrees <= 20.0 -> 9.8
        fovDegrees <= 65.0 -> 7.6
        else -> 6.0
    }
    val dsoStroke = if (palette.isNightVision) palette.primaryRed.copy(alpha = 0.78f) else Color(0xFFC084FC).copy(alpha = 0.78f)
    val dash = PathEffect.dashPathEffect(floatArrayOf(5f, 4f), 0f)
    labelPaint.color = if (palette.isNightVision) 0xCCFF1824.toInt() else 0xDDD8B4FE.toInt()
    labelPaint.textSize = 21f

    for (dso in state.dsos) {
        if (dso.visualMag > maxDsoMag) continue
        val p = proj.projectEQJUnitVector(dso.ux.toDouble(), dso.uy.toDouble(), dso.uz.toDouble()) ?: continue
        if (!p.isVisible) continue

        val sx = p.x.toFloat()
        val sy = p.y.toFloat()
        val angularDeg = (dso.majorAxisArcmin / 60.0).coerceAtLeast(0.12)
        val pxRadius = ((angularDeg / fovDegrees) * size.minDimension * 0.5).toFloat().coerceIn(5.5f, 34f)

        when {
            dso.type.contains("Galaxy", ignoreCase = true) -> {
                val ratio = (dso.minorAxisArcmin / max(1.0, dso.majorAxisArcmin)).toFloat().coerceIn(0.35f, 0.9f)
                rotate(degrees = dso.positionAngleDeg.toFloat(), pivot = Offset(sx, sy)) {
                    drawOval(
                        color = dsoStroke,
                        topLeft = Offset(sx - pxRadius, sy - pxRadius * ratio),
                        size = Size(pxRadius * 2f, pxRadius * 2f * ratio),
                        style = Stroke(width = 1.5f)
                    )
                }
            }
            dso.type.contains("Cluster", ignoreCase = true) -> {
                drawCircle(dsoStroke, radius = pxRadius, center = Offset(sx, sy), style = Stroke(width = 1.5f, pathEffect = dash))
            }
            else -> {
                val diamond = Path().apply {
                    moveTo(sx, sy - pxRadius)
                    lineTo(sx + pxRadius, sy)
                    lineTo(sx, sy + pxRadius)
                    lineTo(sx - pxRadius, sy)
                    close()
                }
                drawPath(diamond, color = dsoStroke, style = Stroke(width = 1.5f))
            }
        }

        candidates.add(TapCandidate(CosmosSearchResult.DSO(dso), sx, sy, 8f))
        if (fovDegrees <= 45.0 || dso.visualMag <= 5.5) {
            drawContext.canvas.nativeCanvas.drawText(dso.id, sx + pxRadius + 5f, sy + 5f, labelPaint)
        }
    }
}

private fun DrawScope.drawMeteorRadiants(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    val radColor = if (palette.isNightVision) palette.primaryRed else Color(0xFF34D399)
    labelPaint.color = if (palette.isNightVision) 0xDDFF1824.toInt() else 0xDD6EE7B7.toInt()
    labelPaint.textSize = 21f

    for (shower in state.activeMeteorShowers) {
        val raRad = Math.toRadians(shower.radiantRaHours * 15.0)
        val decRad = Math.toRadians(shower.radiantDecDeg)
        val p = proj.projectEQJUnitVector(cos(decRad) * cos(raRad), cos(decRad) * sin(raRad), sin(decRad)) ?: continue
        if (!p.isVisible) continue
        val sx = p.x.toFloat()
        val sy = p.y.toFloat()

        for (k in 0 until 6) {
            val a = k * (Math.PI / 3.0)
            val r1 = 6f
            val r2 = 15f
            drawLine(
                radColor.copy(alpha = 0.75f),
                Offset(sx + (cos(a) * r1).toFloat(), sy + (sin(a) * r1).toFloat()),
                Offset(sx + (cos(a) * r2).toFloat(), sy + (sin(a) * r2).toFloat()),
                strokeWidth = 1.4f
            )
        }
        drawContext.canvas.nativeCanvas.drawText("${shower.name} (ZHR ${shower.zhr})", sx + 16f, sy + 5f, labelPaint)
        candidates.add(TapCandidate(CosmosSearchResult.Shower(shower), sx, sy, 6f))
    }
}

private fun DrawScope.drawSolarSystemBodies(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    fovDegrees: Double,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    subPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    labelPaint.textSize = 25f
    subPaint.textSize = 20f

    for ((body, coords) in state.allBodies) {
        val p = proj.projectHorizontal(coords.azimuthDegrees, coords.altitudeDegrees, margin = 45.0) ?: continue
        if (!p.isVisible) continue
        if (state.showAtmosphere && coords.altitudeDegrees < -2.0 && fovDegrees > 20.0) continue

        val sx = p.x.toFloat()
        val sy = p.y.toFloat()
        val zoomScale = (60.0 / fovDegrees.coerceIn(0.6, 120.0)).pow(0.42).toFloat().coerceIn(0.85f, 5.2f)

        val bodyColor = if (palette.isNightVision) {
            palette.primaryRed
        } else {
            runCatching { Color(android.graphics.Color.parseColor(body.colorHex)) }.getOrDefault(Color.White)
        }

        when (body) {
            CelestialBody.SUN -> {
                val r = 9.5f * zoomScale
                drawCircle(bodyColor.copy(alpha = 0.25f), radius = r * 2.4f, center = Offset(sx, sy))
                drawCircle(bodyColor, radius = r, center = Offset(sx, sy))
            }

            CelestialBody.MOON -> {
                val r = (8.8f * zoomScale).coerceIn(7f, 44f)
                val k = (state.moon?.illuminatedFraction ?: coords.illuminatedFraction).toFloat().coerceIn(0f, 1f)
                val limbAngle = (state.moon?.brightLimbAngleDegrees ?: coords.brightLimbAngleDegrees).toFloat()

                // Earthshine dark lunar limb
                val darkColor = if (palette.isNightVision) Color(0xFF280205) else Color(0xFF1A2234)
                val litColor = if (palette.isNightVision) palette.primaryRed else Color(0xFFF4F1DE)
                drawCircle(litColor.copy(alpha = 0.18f), radius = r * 1.9f, center = Offset(sx, sy))
                drawCircle(darkColor, radius = r, center = Offset(sx, sy))

                // Spherical terminator rotated by exact bright-limb position angle χ (CCW from local zenith-up)
                val moonClip = Path().apply {
                    addOval(androidx.compose.ui.geometry.Rect(sx - r, sy - r, sx + r, sy + r))
                }
                clipPath(moonClip) {
                    // Rotate so bright limb points to +X (screen right), then draw lit hemisphere + terminator ellipse
                    rotate(degrees = 90f - limbAngle, pivot = Offset(sx, sy)) {
                        drawArc(
                            color = litColor,
                            startAngle = -90f,
                            sweepAngle = 180f,
                            useCenter = true,
                            topLeft = Offset(sx - r, sy - r),
                            size = Size(r * 2f, r * 2f)
                        )
                        val termRx = abs(2f * k - 1f) * r
                        if (termRx > 0.4f) {
                            drawOval(
                                color = if (k >= 0.5f) litColor else darkColor,
                                topLeft = Offset(sx - termRx, sy - r),
                                size = Size(termRx * 2f, r * 2f)
                            )
                        }
                    }
                }
                drawCircle(litColor.copy(alpha = 0.45f), radius = r, center = Offset(sx, sy), style = Stroke(width = 1f))
            }

            CelestialBody.SATURN -> {
                val r = (5.4f * zoomScale).coerceIn(4.5f, 24f)
                val ringTiltRad = Math.toRadians(abs(state.saturnRingTiltDegrees)).coerceIn(0.06, 0.55)
                val ringRx = r * 2.35f
                val ringRy = (ringRx * sin(ringTiltRad).toFloat()).coerceAtLeast(1.8f)
                rotate(degrees = -14f, pivot = Offset(sx, sy)) {
                    drawOval(
                        color = bodyColor.copy(alpha = 0.82f),
                        topLeft = Offset(sx - ringRx, sy - ringRy),
                        size = Size(ringRx * 2f, ringRy * 2f),
                        style = Stroke(width = max(1.6f, r * 0.24f))
                    )
                }
                drawCircle(bodyColor.copy(alpha = 0.22f), radius = r * 1.9f, center = Offset(sx, sy))
                drawCircle(bodyColor, radius = r, center = Offset(sx, sy))
            }

            CelestialBody.JUPITER -> {
                val r = (6.0f * zoomScale).coerceIn(5.0f, 28f)
                drawCircle(bodyColor.copy(alpha = 0.24f), radius = r * 1.9f, center = Offset(sx, sy))
                drawCircle(bodyColor, radius = r, center = Offset(sx, sy))
                if (fovDegrees <= 15.0) {
                    val bandCol = if (palette.isNightVision) Color(0xFF5A050A) else Color(0xFFB47B56)
                    drawLine(bandCol, Offset(sx - r * 0.85f, sy - r * 0.25f), Offset(sx + r * 0.85f, sy - r * 0.25f), strokeWidth = max(1.2f, r * 0.16f))
                    drawLine(bandCol, Offset(sx - r * 0.85f, sy + r * 0.25f), Offset(sx + r * 0.85f, sy + r * 0.25f), strokeWidth = max(1.2f, r * 0.16f))
                }
                // Live 4 Galilean Moons (Io, Europa, Ganymede, Callisto) in Binocular / Telescope Zoom!
                if (fovDegrees <= 12.0 && state.jupiterMoons != null) {
                    subPaint.color = if (palette.isNightVision) 0xDDFF1824.toInt() else 0xFFE2E8F0.toInt()
                    for (gm in state.jupiterMoons.all) {
                        if (gm.isOcculted) continue
                        val mx = sx + (gm.xRadius.toFloat() * r * 1.15f)
                        val my = sy - (gm.yRadius.toFloat() * r * 1.15f)
                        drawCircle(bodyColor, radius = 2.6f, center = Offset(mx, my))
                        if (fovDegrees <= 4.5) {
                            drawContext.canvas.nativeCanvas.drawText(gm.name, mx + 5f, my - 4f, subPaint)
                        }
                    }
                }
            }

            else -> {
                val r = (4.6f * zoomScale).coerceIn(3.8f, 18f)
                drawCircle(bodyColor.copy(alpha = 0.25f), radius = r * 2.0f, center = Offset(sx, sy))
                drawCircle(bodyColor, radius = r, center = Offset(sx, sy))
            }
        }

        labelPaint.color = if (palette.isNightVision) 0xFFFF1824.toInt() else 0xFFF8FAFC.toInt()
        drawContext.canvas.nativeCanvas.drawText(body.displayName, sx + 12f, sy + 5f, labelPaint)
        candidates.add(TapCandidate(CosmosSearchResult.Planet(body), sx, sy, 14f))
    }
}

private fun DrawScope.drawIssSatelliteAndTrajectory(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette,
    labelPaint: Paint,
    candidates: MutableList<TapCandidate>
) {
    // Trajectory arc for next / active visible pass (sunlit solid vs Earth-shadow dashed)
    val pass = state.issPasses.firstOrNull()
    if (pass != null && pass.trajectory.size >= 2) {
        val sunlitCol = if (palette.isNightVision) palette.primaryRed else Color(0xFFFFD166)
        val umbraCol = palette.fgMuted.copy(alpha = 0.38f)
        val dash = PathEffect.dashPathEffect(floatArrayOf(7f, 6f), 0f)
        var prevPt: Offset? = null
        var prevSunlit = true
        for (sample in pass.trajectory) {
            val sp = proj.projectHorizontal(sample.azimuthDegrees, sample.altitudeDegrees, margin = 120.0)
            if (sp != null) {
                val cur = Offset(sp.x.toFloat(), sp.y.toFloat())
                if (prevPt != null && hypot(cur.x - prevPt.x, cur.y - prevPt.y) < size.width * 0.45f) {
                    val lit = sample.isSunlit && prevSunlit
                    drawLine(
                        color = if (lit) sunlitCol.copy(alpha = 0.72f) else umbraCol,
                        start = prevPt,
                        end = cur,
                        strokeWidth = if (lit) 2.0f else 1.3f,
                        pathEffect = if (lit) null else dash
                    )
                }
                prevPt = cur
                prevSunlit = sample.isSunlit
            } else {
                prevPt = null
            }
        }
    }

    val iss = state.issLivePosition ?: return
    val p = proj.projectHorizontal(iss.azimuthDegrees, iss.altitudeDegrees, margin = 40.0) ?: return
    if (!p.isVisible) return

    val sx = p.x.toFloat()
    val sy = p.y.toFloat()
    val col = if (palette.isNightVision) palette.primaryRed else if (iss.isSunlit) Color(0xFFFFD166) else Color(0xFF94A3B8)

    drawCircle(col.copy(alpha = 0.25f), radius = 14f, center = Offset(sx, sy))
    drawCircle(col, radius = 4.5f, center = Offset(sx, sy))
    drawLine(col, Offset(sx - 11f, sy), Offset(sx - 5f, sy), strokeWidth = 2.2f)
    drawLine(col, Offset(sx + 5f, sy), Offset(sx + 11f, sy), strokeWidth = 2.2f)

    labelPaint.color = if (palette.isNightVision) 0xFFFF1824.toInt() else 0xFFFFD166.toInt()
    labelPaint.textSize = 23f
    drawContext.canvas.nativeCanvas.drawText("ISS", sx + 14f, sy + 6f, labelPaint)
    candidates.add(TapCandidate(CosmosSearchResult.IssStation, sx, sy, 16f))
}

private fun DrawScope.drawHorizonAndCompass(
    proj: SkyProjectionMatrix,
    cameraAzimuth: Double,
    cameraAltitude: Double,
    palette: AndroidCosmosPalette,
    labelPaint: Paint
) {
    // Forward-hemisphere mathematical horizon curve + opaque landscape ground apron (alt < 0°)
    val horizonPts = ArrayList<Offset>(72)
    var lastX = Float.NEGATIVE_INFINITY
    val marginPx = max(size.width, size.height) * 0.9
    for (offset in -102..102 step 3) {
        val az = ((cameraAzimuth + offset) % 360.0 + 360.0) % 360.0
        val azRad = Math.toRadians(az)
        val cz = proj.fx * cos(azRad) + proj.fy * (-sin(azRad))
        if (cz <= 0.05) continue
        val p = proj.projectHorizontal(az, 0.0, margin = marginPx) ?: continue
        val sx = p.x.toFloat()
        if (sx > lastX) {
            lastX = sx
            horizonPts.add(Offset(sx, p.y.toFloat()))
        }
    }

    if (cameraAltitude < 65.0 && horizonPts.size >= 2) {
        val groundFill = if (palette.isNightVision) {
            Color(0xEC070001)
        } else {
            Color(0xEC040812)
        }
        val groundPath = Path().apply {
            val first = horizonPts.first()
            val last = horizonPts.last()
            val bottomY = max(size.height + 80f, max(first.y, last.y) + 500f)
            moveTo(first.x, first.y)
            for (i in 1 until horizonPts.size) {
                lineTo(horizonPts[i].x, horizonPts[i].y)
            }
            lineTo(last.x, bottomY)
            lineTo(first.x, bottomY)
            close()
        }
        drawPath(groundPath, color = groundFill)
    }

    val horizonLineColor = palette.accent.copy(alpha = 0.62f)
    for (i in 0 until horizonPts.size - 1) {
        val a = horizonPts[i]
        val b = horizonPts[i + 1]
        if (b.x > a.x && hypot(a.x - b.x, a.y - b.y) < size.width * 0.45f) {
            drawLine(horizonLineColor, a, b, strokeWidth = 2.0f)
        }
    }

    // 8 Cardinal & Intercardinal Compass Beacons along the mathematical horizon
    val cardinals = listOf(
        Triple("N", 0.0, true),
        Triple("NE", 45.0, false),
        Triple("E", 90.0, true),
        Triple("SE", 135.0, false),
        Triple("S", 180.0, true),
        Triple("SW", 225.0, false),
        Triple("W", 270.0, true),
        Triple("NW", 315.0, false)
    )
    for ((label, az, isPrimary) in cardinals) {
        val p = proj.projectHorizontal(az, 0.0, margin = 24.0) ?: continue
        if (!p.isVisible) continue
        val cx = p.x.toFloat()
        val cy = p.y.toFloat()

        val pillR = if (isPrimary) 16f else 12f
        drawCircle(palette.cardBg, radius = pillR, center = Offset(cx, cy - 18f))
        drawCircle(
            if (label == "N") palette.accent else palette.border,
            radius = pillR,
            center = Offset(cx, cy - 18f),
            style = Stroke(width = if (label == "N") 1.8f else 1.0f)
        )
        labelPaint.textSize = if (isPrimary) 24f else 19f
        labelPaint.color = if (palette.isNightVision) {
            0xFFFF1824.toInt()
        } else if (label == "N") {
            0xFF00E5FF.toInt()
        } else {
            0xFFE2E8F0.toInt()
        }
        val tw = labelPaint.measureText(label)
        drawContext.canvas.nativeCanvas.drawText(label, cx - tw * 0.5f, cy - 10f, labelPaint)
    }
}

private fun DrawScope.drawTargetSelectionAndGuideArrow(
    state: CosmosViewState,
    proj: SkyProjectionMatrix,
    palette: AndroidCosmosPalette
) {
    val metrics = state.selectedTargetMetrics ?: return
    val p = proj.projectHorizontal(metrics.azimuthDegrees, metrics.altitudeDegrees, margin = 2000.0)
    val cx = size.width * 0.5f
    val cy = size.height * 0.5f

    if (p != null && p.x in 24.0..(size.width - 24.0) && p.y in 24.0..(size.height - 24.0)) {
        val tx = p.x.toFloat()
        val ty = p.y.toFloat()
        drawCircle(palette.accent, radius = 19f, center = Offset(tx, ty), style = Stroke(width = 1.8f))
        drawCircle(palette.accent.copy(alpha = 0.35f), radius = 26f, center = Offset(tx, ty), style = Stroke(width = 1.0f))
        return
    }

    // Off-axis AR Target Guide Arrow on viewport perimeter
    val az = Math.toRadians(metrics.azimuthDegrees)
    val alt = Math.toRadians(metrics.altitudeDegrees)
    val hx = cos(alt) * cos(az)
    val hy = -cos(alt) * sin(az)
    val hz = sin(alt)
    val camX = (proj.rx * hx + proj.ry * hy + proj.rz * hz).toFloat()
    val camY = -(proj.ux * hx + proj.uy * hy + proj.uz * hz).toFloat()
    val angle = atan2(camY, camX)
    val ringR = min(size.width, size.height) * 0.36f
    val ax = cx + cos(angle) * ringR
    val ay = cy + sin(angle) * ringR

    drawCircle(palette.cardBg, radius = 18f, center = Offset(ax, ay))
    drawCircle(palette.accent, radius = 18f, center = Offset(ax, ay), style = Stroke(width = 1.8f))

    val arrowPath = Path().apply {
        val tipX = ax + cos(angle) * 9f
        val tipY = ay + sin(angle) * 9f
        val leftX = ax + cos(angle + 2.4f) * 8f
        val leftY = ay + sin(angle + 2.4f) * 8f
        val rightX = ax + cos(angle - 2.4f) * 8f
        val rightY = ay + sin(angle - 2.4f) * 8f
        moveTo(tipX, tipY)
        lineTo(leftX, leftY)
        lineTo(rightX, rightY)
        close()
    }
    drawPath(arrowPath, color = palette.accent)
}

// ============================================================================
// TARGET INSPECTOR CARD (LIVE METRICS + DSO THUMBNAIL + BOOKMARK + #SKY TAGDOS)
// ============================================================================

@Composable
private fun TargetInspectorCard(
    viewModel: CosmosViewModel,
    target: CosmosSearchResult,
    metrics: TargetLiveMetrics?,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onScheduleTarget: () -> Unit,
    onDismiss: () -> Unit
) {
    val isBookmarked = remember(state.bookmarks, target) { viewModel.isBookmarked(target) }
    val thumb = remember(target) {
        (target as? CosmosSearchResult.DSO)?.dso?.thumbnail?.let {
            viewModel.catalogRepository.loadDsoThumbnail(it)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(18.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (thumb != null) {
                Image(
                    bitmap = thumb,
                    contentDescription = target.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .border(1.dp, palette.border, RoundedCornerShape(10.dp))
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = target.title,
                    color = palette.fgPrimary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = target.subtitle,
                    color = palette.fgSecondary,
                    fontSize = 11.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Icon(
                imageVector = if (isBookmarked) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                contentDescription = if (isBookmarked) "Remove Bookmark" else "Bookmark Sky Object",
                tint = palette.accent,
                modifier = Modifier
                    .size(22.dp)
                    .clickable { viewModel.toggleBookmark(target) }
            )

            Icon(
                imageVector = Icons.Rounded.Close,
                contentDescription = "Dismiss Inspector",
                tint = palette.fgMuted,
                modifier = Modifier
                    .size(22.dp)
                    .clickable { onDismiss() }
            )
        }

        if (metrics != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                InspectorStatChip(
                    label = "AZ / ALT",
                    value = "${metrics.azimuthDegrees.roundToInt()}° ${CelestialCoordinates.compassPoint(metrics.azimuthDegrees)} · ${"%+d°".format(metrics.altitudeDegrees.roundToInt())}",
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                InspectorStatChip(
                    label = "RA / DEC",
                    value = "${"%.2fh".format(metrics.raHours)} · ${"%+.1f°".format(metrics.decDegrees)}",
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                InspectorStatChip(
                    label = "DIST / INFO",
                    value = metrics.distanceLabel ?: "--",
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }

            metrics.riseTransitSet?.let { rts ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Rise ${formatMillisShort(rts.riseMillis)}", color = palette.fgMuted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    Text("Transit ${formatMillisShort(rts.transitMillis)}", color = palette.accent, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    Text("Set ${formatMillisShort(rts.setMillis)}", color = palette.fgMuted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }

        // Action Row: Center, Log #sky Sighting to TagDoS, Schedule Observation
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            InspectorActionButton(
                icon = Icons.Rounded.CenterFocusStrong,
                label = "Center",
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { viewModel.centerOnSelectedTarget() }
            )
            InspectorActionButton(
                icon = Icons.Rounded.EditNote,
                label = "Log #sky",
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { viewModel.logSightingToTagdos(target) }
            )
            InspectorActionButton(
                icon = Icons.Rounded.CalendarMonth,
                label = "Schedule",
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = onScheduleTarget
            )
        }
    }
}

@Composable
private fun InspectorStatChip(
    label: String,
    value: String,
    palette: AndroidCosmosPalette,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(palette.pillBg)
            .padding(horizontal = 8.dp, vertical = 6.dp)
    ) {
        Text(label, color = palette.fgMuted, fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
        Text(value, color = palette.fgPrimary, fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun InspectorActionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    palette: AndroidCosmosPalette,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(palette.pillBg)
            .border(1.dp, palette.border, CircleShape)
            .clickable { onClick() }
            .padding(vertical = 7.dp, horizontal = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = palette.accent, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(4.dp))
        Text(label, color = palette.fgPrimary, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

// ============================================================================
// CONTINUOUS TIME MACHINE CARD (±12H SLIDER + 1900–2100 DATE JUMP)
// ============================================================================

@Composable
private fun ContinuousTimeMachineCard(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var lastHourBucket by remember { mutableStateOf((state.timeOffsetMinutes / 60.0).toInt()) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "TIME MACHINE (±12H SCRUBBER)",
                color = palette.fgMuted,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )

            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(palette.pillBg)
                    .border(1.dp, palette.border, CircleShape)
                    .clickable {
                        val cal = Calendar.getInstance().apply { timeInMillis = state.effectiveTimestamp }
                        DatePickerDialog(
                            context,
                            { _, y, m, d ->
                                val picked = Calendar.getInstance().apply {
                                    set(y, m, d, 22, 0, 0)
                                }
                                viewModel.jumpToTimestamp(picked.timeInMillis)
                            },
                            cal.get(Calendar.YEAR).coerceIn(1900, 2100),
                            cal.get(Calendar.MONTH),
                            cal.get(Calendar.DAY_OF_MONTH)
                        ).show()
                    }
                    .padding(horizontal = 8.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Rounded.CalendarMonth, contentDescription = null, tint = palette.accent, modifier = Modifier.size(12.dp))
                Text("1900–2100 Jump", color = palette.fgPrimary, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        Slider(
            value = state.timeOffsetMinutes.toFloat().coerceIn(-720f, 720f),
            onValueChange = { mins ->
                val bucket = (mins / 60f).toInt()
                if (bucket != lastHourBucket) {
                    lastHourBucket = bucket
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                }
                viewModel.setTimeOffsetMinutes(mins.toDouble())
            },
            valueRange = -720f..720f,
            colors = SliderDefaults.colors(
                thumbColor = palette.accent,
                activeTrackColor = palette.accent,
                inactiveTrackColor = palette.border
            )
        )
    }
}

// ============================================================================
// UNFOLDED 42% OBSERVATORY SIDE DECK & TABLETOP FLEX CONSOLE
// ============================================================================

@Composable
private fun ObservatorySideDeck(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onSchedulePass: (SatellitePass) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text("OBSERVATORY DECK", color = palette.accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                Text(state.locationName, color = palette.fgPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(palette.pillBg)
                    .border(1.dp, palette.border, CircleShape)
                    .clickable { viewModel.refreshLiveTelemetry() },
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.Refresh, contentDescription = "Refresh Live Sky Telemetry", tint = palette.accent, modifier = Modifier.size(16.dp))
            }
        }

        ObservatoryTelemetryCards(
            viewModel = viewModel,
            state = state,
            palette = palette,
            onSchedulePass = onSchedulePass
        )
    }
}

@Composable
private fun TabletopObservatoryConsole(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onOpenLayers: () -> Unit,
    onOpenSearch: () -> Unit,
    onSchedulePass: (SatellitePass) -> Unit,
    modifier: Modifier = Modifier
) {
    val cameraState by viewModel.cameraState.collectAsState()

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SmallPillButton(
                label = if (cameraState.isArGyroActive) "AR Gyro ON" else "AR Gyro",
                palette = palette,
                isActive = cameraState.isArGyroActive,
                onClick = { viewModel.toggleArGyro() }
            )
            SmallPillButton(
                label = if (state.isNightVisionMode) "Red Vision ON" else "Red Vision",
                palette = palette,
                isActive = state.isNightVisionMode,
                onClick = { viewModel.toggleNightVision() }
            )
            SmallPillButton("Layers", palette = palette, onClick = onOpenLayers)
            SmallPillButton("Search", palette = palette, onClick = onOpenSearch)
            Spacer(Modifier.weight(1f))
            SmallPillButton("-1h", palette = palette) { viewModel.shiftTime(-1.0) }
            SmallPillButton("LIVE", palette = palette, isActive = state.isLiveTime) { viewModel.resetToLiveTime() }
            SmallPillButton("+1h", palette = palette) { viewModel.shiftTime(1.0) }
        }

        state.selectedTarget?.let { target ->
            TargetInspectorCard(
                viewModel = viewModel,
                target = target,
                metrics = state.selectedTargetMetrics,
                state = state,
                palette = palette,
                onScheduleTarget = {},
                onDismiss = { viewModel.selectTarget(null) }
            )
        }

        ObservatoryTelemetryCards(
            viewModel = viewModel,
            state = state,
            palette = palette,
            onSchedulePass = onSchedulePass
        )
    }
}

@Composable
private fun ObservatoryTelemetryCards(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onSchedulePass: (SatellitePass) -> Unit
) {
    val cond = state.conditions

    // 1. Stargazing Score & Multi-Altitude Cloud / Seeing Card
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("STARGAZING QUALITY", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(cond?.provenance?.badgeLabel ?: "Offline", color = palette.accent, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        }

        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${cond?.score ?: "--"}", color = palette.fgPrimary, fontSize = 36.sp, fontWeight = FontWeight.Light)
            Column(modifier = Modifier.padding(bottom = 4.dp)) {
                Text(cond?.quality?.displayName ?: "Evaluating", color = palette.accent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Text(
                    text = "Bortle ${cond?.bortleClass ?: 5} · NELM ${"%.1f".format(cond?.limitingMagnitude ?: 5.8)}",
                    color = palette.fgSecondary,
                    fontSize = 11.sp
                )
            }
        }

        cond?.bestWindowDescription?.let { win ->
            Text("Best Dark Window: $win", color = palette.positive, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold)
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            InspectorStatChip(
                label = "CLOUDS (L/M/H)",
                value = if (cond?.cloudCoverTotalPercent != null) {
                    "${cond.cloudCoverTotalPercent}% (${cond.cloudCoverLowPercent ?: 0}/${cond.cloudCoverMidPercent ?: 0}/${cond.cloudCoverHighPercent ?: 0})"
                } else "Offline",
                palette = palette,
                modifier = Modifier.weight(1f)
            )
            InspectorStatChip(
                label = "SEEING",
                value = cond?.seeingArcseconds?.let { "${"%.1f".format(it)}\" · ${cond.transparencyLabel ?: "Good"}" } ?: "Offline",
                palette = palette,
                modifier = Modifier.weight(1f)
            )
        }

        cond?.narrativeAdvice?.let {
            Text(it, color = palette.fgSecondary, fontSize = 11.5.sp)
        }
    }

    // 2. NOAA Space Weather & Aurora Telemetry
    val sw = state.spaceWeather
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("NOAA SPACE WEATHER", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(sw.provenance.badgeLabel, color = palette.accent, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            InspectorStatChip("KP INDEX", sw.kpIndex?.let { "Kp ${"%.1f".format(it)}" } ?: "Offline", palette, Modifier.weight(1f))
            InspectorStatChip("IMF BZ", sw.bzMagneticFieldNt?.let { "${"%+.1f".format(it)} nT" } ?: "Offline", palette, Modifier.weight(1f))
            InspectorStatChip("SOLAR WIND", sw.solarWindSpeedKmS?.let { "${it.roundToInt()} km/s" } ?: "Offline", palette, Modifier.weight(1f))
        }
        Text(sw.statusMessage, color = palette.fgSecondary, fontSize = 11.sp)
    }

    // 3. Visible Solar System Bodies Carousel
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("SOLAR SYSTEM EPHEMERIS", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(state.allBodies.filter { it.first != CelestialBody.SUN }) { (body, coords) ->
                Column(
                    modifier = Modifier
                        .width(106.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(palette.pillBg)
                        .border(1.dp, if (coords.isVisible) palette.accent.copy(alpha = 0.45f) else palette.border, RoundedCornerShape(12.dp))
                        .clickable { viewModel.selectTarget(CosmosSearchResult.Planet(body), centerCamera = true) }
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Text("${body.symbol} ${body.displayName}", color = palette.fgPrimary, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text(
                        text = if (coords.isVisible) "Alt +${coords.altitudeDegrees.roundToInt()}° ${coords.compassDirection}" else "Below (${coords.altitudeDegrees.roundToInt()}°)",
                        color = if (coords.isVisible) palette.positive else palette.fgMuted,
                        fontSize = 10.5.sp,
                        maxLines = 1
                    )
                    Text("mag ${"%.1f".format(coords.visualMagnitude)}", color = palette.fgSecondary, fontSize = 10.sp)
                }
            }
        }
    }

    // 4. Real SGP4 ISS Passes
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("ISS VISIBLE SGP4 PASSES", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(state.issProvenance.badgeLabel, color = palette.accent, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        }
        if (state.issPasses.isEmpty()) {
            Text(
                text = if (state.issProvenance.isAvailable) "No sunlit twilight/night ISS passes above 10° in the next 48 hours."
                else "Connect once to cache CelesTrak GP orbital elements for offline SGP4 pass prediction.",
                color = palette.fgSecondary,
                fontSize = 11.5.sp
            )
        } else {
            state.issPasses.take(3).forEach { pass ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(palette.pillBg)
                        .clickable { viewModel.selectTarget(CosmosSearchResult.IssStation, centerCamera = true) }
                        .padding(10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "${formatMillisShort(pass.startTimeMillis)} · Peak ${pass.maxAltitudeDegrees.roundToInt()}° (${pass.durationMinutes}m)",
                            color = palette.fgPrimary,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "${pass.startCompass} → ${pass.endCompass} · mag ${"%.1f".format(pass.peakMagnitude)}",
                            color = palette.fgSecondary,
                            fontSize = 10.5.sp
                        )
                    }
                    SmallPillButton("Schedule", palette = palette) { onSchedulePass(pass) }
                }
            }
        }
    }

    // 5. Showcase Messier & Caldwell Deep-Sky Targets
    val showcaseDsos = remember(state.dsos) { state.dsos.filter { !it.thumbnail.isNullOrBlank() }.take(8) }
    if (showcaseDsos.isNotEmpty()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(palette.cardBg)
                .border(1.dp, palette.border, RoundedCornerShape(16.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("DEEP-SKY SHOWCASE (MESSIER & CALDWELL)", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(showcaseDsos) { dso ->
                    val bmp = remember(dso.thumbnail) { viewModel.catalogRepository.loadDsoThumbnail(dso.thumbnail) }
                    Column(
                        modifier = Modifier
                            .width(128.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.pillBg)
                            .border(1.dp, palette.border, RoundedCornerShape(12.dp))
                            .clickable { viewModel.selectTarget(CosmosSearchResult.DSO(dso), centerCamera = true) }
                            .padding(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        if (bmp != null) {
                            Image(
                                bitmap = bmp,
                                contentDescription = dso.name,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(68.dp)
                                    .clip(RoundedCornerShape(8.dp))
                            )
                        }
                        Text("${dso.id} · ${dso.name}", color = palette.fgPrimary, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${dso.type} · mag ${"%.1f".format(dso.visualMag)}", color = palette.fgSecondary, fontSize = 9.5.sp, maxLines = 1)
                    }
                }
            }
        }
    }

    // 6. NASA Astronomy Picture of the Day (APOD)
    state.apod?.let { apod ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(palette.cardBg)
                .border(1.dp, palette.border, RoundedCornerShape(16.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("NASA APOD · ${apod.date}", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(state.apodProvenance.badgeLabel, color = palette.accent, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
            }
            Text(apod.title, color = palette.fgPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.Bold)
            Text(apod.explanation, color = palette.fgSecondary, fontSize = 11.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
        }
    }

    // 7. Circadian & Lunar Sleep Context
    state.circadianContext?.let { circ ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(palette.cardBg)
                .border(1.dp, palette.border, RoundedCornerShape(16.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text("CIRCADIAN & LUNAR SKYGLOW", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(circ.summary, color = palette.fgSecondary, fontSize = 11.5.sp)
        }
    }

    // 8. Synchronized Sky Bookmarks (Supabase Cloud + Local Cache)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("SKY BOOKMARKS (${state.bookmarks.size})", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text("CLOUD SYNC", color = palette.accent, fontSize = 9.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        }

        if (state.bookmarks.isEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(palette.pillBg.copy(alpha = 0.6f))
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Rounded.BookmarkBorder, contentDescription = null, tint = palette.fgMuted, modifier = Modifier.size(16.dp))
                Text(
                    "No bookmarks saved yet. Tap the bookmark icon on any celestial object to sync across all devices.",
                    color = palette.fgMuted,
                    fontSize = 11.5.sp
                )
            }
        } else {
            state.bookmarks.forEach { bm ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(palette.pillBg)
                        .clickable { viewModel.selectTarget(viewModel.targetForBookmark(bm), centerCamera = true) }
                        .padding(10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Rounded.Bookmark, contentDescription = null, tint = palette.accent, modifier = Modifier.size(15.dp))
                        Column {
                            Text(bm.objectName, color = palette.fgPrimary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
                            Text(
                                text = "${bm.category}${bm.constellation?.let { " · $it" } ?: ""}",
                                color = palette.fgSecondary,
                                fontSize = 10.sp
                            )
                        }
                    }
                    Icon(
                        Icons.Rounded.Delete,
                        contentDescription = "Remove bookmark",
                        tint = palette.fgMuted,
                        modifier = Modifier
                            .size(18.dp)
                            .clickable { viewModel.removeBookmark(bm.objectId, bm.objectName, bm.category) }
                    )
                }
            }
        }
    }

    // 9. Logged Sky Sightings & Observations (#sky TagDoS + Supabase)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(palette.cardBg)
            .border(1.dp, palette.border, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("OBSERVATIONS & LOGGED SIGHTINGS (${state.observations.size})", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text("#SKY TAGDOS", color = palette.positive, fontSize = 9.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        }

        if (state.observations.isEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(palette.pillBg.copy(alpha = 0.6f))
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Rounded.EditNote, contentDescription = null, tint = palette.fgMuted, modifier = Modifier.size(16.dp))
                Text(
                    "No sky observations logged yet. Select any celestial object and tap 'Log Sighting (#sky)' to record observations.",
                    color = palette.fgMuted,
                    fontSize = 11.5.sp
                )
            }
        } else {
            state.observations.forEach { obs ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(palette.pillBg)
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = palette.positive, modifier = Modifier.size(14.dp))
                            Text(obs.objectName, color = palette.fgPrimary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(obs.category.uppercase(), color = palette.fgMuted, fontSize = 9.5.sp)
                            Icon(
                                Icons.Rounded.Delete,
                                contentDescription = "Delete observation",
                                tint = palette.fgMuted,
                                modifier = Modifier
                                    .size(16.dp)
                                    .clickable { viewModel.deleteObservation(obs.id) }
                            )
                        }
                    }

                    Text(
                        text = "${obs.observedAt.take(16).replace('T', ' ')} · ${obs.optics}",
                        color = palette.fgSecondary,
                        fontSize = 10.5.sp
                    )

                    if (obs.bortleClass != null && obs.stargazingScore != null) {
                        Text(
                            text = "Bortle ${obs.bortleClass} · Sky Score ${obs.stargazingScore}/100 · ${obs.locationName.ifBlank { "Local Horizon" }}",
                            color = palette.fgMuted,
                            fontSize = 9.5.sp
                        )
                    }

                    if (obs.notes.isNotBlank()) {
                        Text(obs.notes, color = palette.fgSecondary, fontSize = 10.5.sp, maxLines = 3)
                    }
                }
            }
        }
    }
}

// ============================================================================
// MODALS: SEARCH, SKY LAYERS & TONIGHT'S BEST DRAWER (STRICT PALETTE)
// ============================================================================

@Composable
private fun CosmosSearchDialog(
    query: String,
    results: List<CosmosSearchResult>,
    bookmarks: List<com.intellidream.daily.model.CosmosBookmark>,
    palette: AndroidCosmosPalette,
    onQueryChanged: (String) -> Unit,
    onSelectResult: (CosmosSearchResult) -> Unit,
    onSelectBookmark: (com.intellidream.daily.model.CosmosBookmark) -> Unit,
    onDismiss: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .clickable { onDismiss() },
        contentAlignment = Alignment.TopCenter
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(16.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(palette.bgDeck)
                .border(1.dp, palette.border, RoundedCornerShape(22.dp))
                .clickable(enabled = false) {}
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Search Celestial Catalog", color = palette.fgPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Icon(Icons.Rounded.Close, contentDescription = "Close Search", tint = palette.fgMuted, modifier = Modifier.clickable { onDismiss() })
            }

            TextField(
                value = query,
                onValueChange = onQueryChanged,
                placeholder = { Text("Stars, Messier/Caldwell, 88 constellations, planets, ISS...", color = palette.fgMuted, fontSize = 12.5.sp) },
                singleLine = true,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = palette.pillBg,
                    unfocusedContainerColor = palette.pillBg,
                    focusedTextColor = palette.fgPrimary,
                    unfocusedTextColor = palette.fgPrimary,
                    cursorColor = palette.accent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .border(1.dp, palette.border, RoundedCornerShape(14.dp))
            )

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 360.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (query.isBlank() && bookmarks.isNotEmpty()) {
                    item {
                        Text("SAVED SKY BOOKMARKS", color = palette.fgMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    items(bookmarks) { bm ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(palette.pillBg)
                                .clickable { onSelectBookmark(bm) }
                                .padding(10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Rounded.Bookmark, contentDescription = null, tint = palette.accent, modifier = Modifier.size(14.dp))
                                Text(bm.objectName, color = palette.fgPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Text(bm.category.uppercase(), color = palette.accent, fontSize = 10.sp)
                        }
                    }
                } else {
                    items(results) { item ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(palette.pillBg)
                                .clickable { onSelectResult(item) }
                                .padding(horizontal = 12.dp, vertical = 9.dp)
                        ) {
                            Text(item.title, color = palette.fgPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                            Text(item.subtitle, color = palette.fgSecondary, fontSize = 11.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CosmosLayersAndEpochModal(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onDismiss: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .clickable { onDismiss() },
        contentAlignment = Alignment.BottomCenter
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(14.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(palette.bgDeck)
                .border(1.dp, palette.border, RoundedCornerShape(22.dp))
                .clickable(enabled = false) {}
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Sky Dome Layers & Grids", color = palette.fgPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Icon(Icons.Rounded.Close, contentDescription = "Close Layers", tint = palette.fgMuted, modifier = Modifier.clickable { onDismiss() })
            }

            LayerToggleRow("Rayleigh Atmosphere & Daylight", state.showAtmosphere, palette) { viewModel.toggleAtmosphere() }
            LayerToggleRow("Milky Way 5-Layer Isophotes", state.showMilkyWay, palette) { viewModel.toggleMilkyWay() }
            LayerToggleRow("88 IAU Constellation Figures", state.showConstellationLines, palette) { viewModel.toggleConstellationLines() }
            LayerToggleRow("IAU Constellation Boundaries", state.showConstellationBorders, palette) { viewModel.toggleConstellationBorders() }
            LayerToggleRow("14 Classical Asterisms", state.showAsterisms, palette) { viewModel.toggleAsterisms() }
            LayerToggleRow("219 Messier & Caldwell DSOs", state.showDeepSkyObjects, palette) { viewModel.toggleDeepSkyObjects() }
            LayerToggleRow("Alt-Azimuth Horizon Grid", state.showAltAzGrid, palette) { viewModel.toggleAltAzGrid() }
            LayerToggleRow("Equatorial J2000 RA/Dec Grid", state.showRaDecGrid, palette) { viewModel.toggleRaDecGrid() }
        }
    }
}

@Composable
private fun LayerToggleRow(
    title: String,
    checked: Boolean,
    palette: AndroidCosmosPalette,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggle() }
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, color = palette.fgPrimary, fontSize = 13.sp)
        Switch(
            checked = checked,
            onCheckedChange = { onToggle() },
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.Black,
                checkedTrackColor = palette.accent,
                uncheckedThumbColor = palette.fgMuted,
                uncheckedTrackColor = palette.pillBg
            )
        )
    }
}

@Composable
private fun CosmosTonightsBestModal(
    viewModel: CosmosViewModel,
    state: CosmosViewState,
    palette: AndroidCosmosPalette,
    onSchedulePass: (SatellitePass) -> Unit,
    onDismiss: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .clickable { onDismiss() },
        contentAlignment = Alignment.BottomCenter
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.82f)
                .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                .background(palette.bgDeck)
                .border(1.dp, palette.border, RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                .clickable(enabled = false) {}
                .navigationBarsPadding()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Tonight's Observatory Briefing", color = palette.fgPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Icon(Icons.Rounded.Close, contentDescription = "Close Briefing", tint = palette.fgMuted, modifier = Modifier.clickable { onDismiss() })
            }

            HorizontalDivider(color = palette.border)
            Spacer(Modifier.height(10.dp))

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ObservatoryTelemetryCards(
                    viewModel = viewModel,
                    state = state,
                    palette = palette,
                    onSchedulePass = onSchedulePass
                )
            }
        }
    }
}

// ============================================================================
// REUSABLE HUD CONTROLS
// ============================================================================

@Composable
private fun HudCircleButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    palette: AndroidCosmosPalette,
    isActive: Boolean = false,
    activeTint: Color = palette.accent,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(if (isActive) activeTint else palette.pillBg)
            .border(1.dp, palette.border, CircleShape)
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = if (isActive) Color.Black else palette.fgPrimary,
            modifier = Modifier.size(16.dp)
        )
    }
}

@Composable
private fun SmallPillButton(
    label: String,
    palette: AndroidCosmosPalette,
    isActive: Boolean = false,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isActive) palette.accent else palette.pillBg)
            .border(1.dp, palette.border, CircleShape)
            .clickable { onClick() }
            .padding(horizontal = 9.dp, vertical = 5.dp)
    ) {
        Text(
            text = label,
            color = if (isActive) Color.Black else palette.fgPrimary,
            fontSize = 10.5.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
    }
}
