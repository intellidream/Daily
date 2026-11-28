package com.intellidream.daily.presentation.loreen

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Create
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockReset
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.updateAll
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.glance.DailyTagdosGlanceWidget
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.LoreenGlyphCatalog
import com.intellidream.daily.model.LoreenGlyphOrigin
import com.intellidream.daily.model.LoreenPoint
import com.intellidream.daily.model.LoreenRecognitionResult
import com.intellidream.daily.model.LoreenStrokeRecognizer
import com.intellidream.daily.model.UserProfile
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun LoreenVeilSettingsCard(
    settings: AppSettings,
    userProfile: UserProfile?,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showInitiationSheet by remember { mutableStateOf(false) }
    var showCodexSheet by remember { mutableStateOf(false) }
    var showRelockDialog by remember { mutableStateOf(false) }

    fun refreshWidgets() {
        scope.launch {
            runCatching { DailyTagdosGlanceWidget().updateAll(context) }
        }
    }

    val statusLabel = when {
        !settings.loreenVeilUnlocked -> "Locked"
        settings.loreenVeilEnabled -> "Active"
        else -> "Ready"
    }
    val statusColor = when {
        !settings.loreenVeilUnlocked -> ThemeColors.accentPurple
        settings.loreenVeilEnabled -> ThemeColors.accentGreen
        else -> ThemeColors.accentCyan
    }

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = if (settings.loreenVeilUnlocked) Icons.Rounded.VisibilityOff else Icons.Rounded.Lock,
                    contentDescription = "Loreen Veil",
                    tint = if (settings.loreenVeilEnabled) ThemeColors.accentCyan else ThemeColors.accentPurple,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Loreen Veil",
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.weight(1f))
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(statusColor.copy(alpha = 0.16f))
                        .padding(horizontal = 9.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = statusLabel,
                        color = statusColor,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            if (!settings.loreenVeilUnlocked) {
                Text(
                    text = "Visual Privacy Shield for Tagdos & Notes. Demonstrate fluency in Loreen Script to unlock.",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 12.sp,
                    lineHeight = 17.sp
                )

                Button(
                    onClick = { showInitiationSheet = true },
                    colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Create,
                        contentDescription = null,
                        tint = Color.Black,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Prove Fluency to Unlock",
                        color = Color.Black,
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Enable Loreen Veil",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Switch(
                        checked = settings.loreenVeilEnabled,
                        onCheckedChange = { enabled ->
                            onUpdateSettings { it.copy(loreenVeilEnabled = enabled) }
                            refreshWidgets()
                        },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.Black,
                            checkedTrackColor = ThemeColors.accentCyan
                        )
                    )
                }

                // Live Sparkle Decrypt Preview Strip
                val stripAccent = if (settings.loreenVeilEnabled) ThemeColors.accentCyan else ThemeColors.accentPurple
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White.copy(alpha = 0.05f))
                        .border(1.dp, stripAccent.copy(alpha = 0.32f), RoundedCornerShape(12.dp))
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = if (settings.loreenVeilEnabled) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                        contentDescription = null,
                        tint = stripAccent,
                        modifier = Modifier.size(14.dp)
                    )
                    LoreenVeilText(
                        text = "Loreen — Secretele tale în siguranță",
                        isVeiled = settings.loreenVeilEnabled,
                        color = Color.White.copy(alpha = 0.92f),
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                LoreenScopeToggleRow(
                    label = "Shield Tagdos Streams & Pills",
                    checked = settings.loreenVeilApplyToTagdos,
                    onCheckedChange = { v ->
                        onUpdateSettings { it.copy(loreenVeilApplyToTagdos = v) }
                        refreshWidgets()
                    }
                )
                LoreenScopeToggleRow(
                    label = "Shield Active Memos & Quick Notes",
                    checked = settings.loreenVeilApplyToNotes,
                    onCheckedChange = { v -> onUpdateSettings { it.copy(loreenVeilApplyToNotes = v) } }
                )
                LoreenScopeToggleRow(
                    label = "Shield Home Screen Widgets",
                    checked = settings.loreenVeilApplyToWidgets,
                    onCheckedChange = { v ->
                        onUpdateSettings { it.copy(loreenVeilApplyToWidgets = v) }
                        refreshWidgets()
                    }
                )
                LoreenScopeToggleRow(
                    label = "Require Biometrics to Reveal",
                    checked = settings.loreenVeilRequireBiometricsForPeek,
                    onCheckedChange = { v -> onUpdateSettings { it.copy(loreenVeilRequireBiometricsForPeek = v) } }
                )

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                            .clickable { showCodexSheet = true }
                            .padding(vertical = 10.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.MenuBook,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(15.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "Loreen Codex & Docs",
                            color = ThemeColors.accentCyan,
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .clickable { showRelockDialog = true }
                            .padding(10.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.LockReset,
                            contentDescription = "Re-lock Loreen Veil",
                            tint = Color.White.copy(alpha = 0.7f),
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }
    }

    if (showInitiationSheet) {
        LoreenInitiationSheet(
            firstName = userProfile?.firstName,
            onUnlocked = {
                onUpdateSettings { it.copy(loreenVeilUnlocked = true, loreenVeilEnabled = true) }
                refreshWidgets()
                showInitiationSheet = false
            },
            onDismiss = { showInitiationSheet = false }
        )
    }

    if (showCodexSheet) {
        LoreenCodexSheet(onDismiss = { showCodexSheet = false })
    }

    if (showRelockDialog) {
        AlertDialog(
            onDismissRequest = { showRelockDialog = false },
            containerColor = Color(0xFF0C182D),
            title = { Text("Re-lock Loreen Veil?", color = Color.White) },
            text = {
                Text(
                    "You will need to pass the Loreen Initiation handwriting check again to re-enable Loreen Veil.",
                    color = Color.White.copy(alpha = 0.75f)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showRelockDialog = false
                    onUpdateSettings { it.copy(loreenVeilUnlocked = false, loreenVeilEnabled = false) }
                    refreshWidgets()
                }) {
                    Text("Re-lock", color = ThemeColors.accentPink)
                }
            },
            dismissButton = {
                TextButton(onClick = { showRelockDialog = false }) {
                    Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                }
            }
        )
    }
}

@Composable
private fun LoreenScopeToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            color = Color.White.copy(alpha = 0.88f),
            fontSize = 13.sp,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = ThemeColors.accentPurple
            )
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun LoreenInitiationSheet(
    firstName: String?,
    onUnlocked: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()

    var useMyName by remember { mutableStateOf(false) }
    var showHintGuides by remember { mutableStateOf(false) }

    val personalWord = remember(firstName) { LoreenGlyphCatalog.challengeWord(firstName) }
    val targetWord = if (useMyName) personalWord else "LOREEN"
    val targetChars = remember(targetWord) { targetWord.toList() }

    val tileStrokes = remember(targetWord) { mutableStateMapOf<Int, List<List<LoreenPoint>>>() }
    val tileVerified = remember(targetWord) { mutableStateMapOf<Int, Boolean>() }
    val tileLastGuess = remember(targetWord) { mutableStateMapOf<Int, Char?>() }

    val verifiedCount = targetChars.indices.count { tileVerified[it] == true }
    val allVerified = targetChars.isNotEmpty() && verifiedCount == targetChars.size

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF060D1A),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                }
                Text("Loreen Initiation", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                TextButton(onClick = {
                    tileStrokes.clear()
                    tileVerified.clear()
                    tileLastGuess.clear()
                }) {
                    Text("Clear All", color = ThemeColors.accentCyan)
                }
            }

            Text(
                text = "Write each letter in Loreen Script to prove fluency and unlock Loreen Veil across Tagdos & Notes.",
                color = Color.White.copy(alpha = 0.75f),
                fontSize = 13.sp
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(14.dp))
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ChallengeModePill(
                        label = "LOREEN",
                        selected = !useMyName,
                        onClick = { useMyName = false },
                        modifier = Modifier.weight(1f)
                    )
                    ChallengeModePill(
                        label = "My Name ($personalWord)",
                        selected = useMyName,
                        onClick = { useMyName = true },
                        modifier = Modifier.weight(1f)
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Progress: $verifiedCount / ${targetChars.size} glyphs verified",
                        color = if (allVerified) ThemeColors.accentGreen else ThemeColors.accentCyan,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Guide", color = Color.White.copy(alpha = 0.65f), fontSize = 11.5.sp)
                        Switch(
                            checked = showHintGuides,
                            onCheckedChange = { showHintGuides = it },
                            colors = SwitchDefaults.colors(checkedTrackColor = ThemeColors.accentPurple)
                        )
                    }
                }
            }

            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                maxItemsInEachRow = 3
            ) {
                targetChars.forEachIndexed { idx, expected ->
                    AndroidLoreenDrawingTile(
                        expectedLetter = expected,
                        showHintGuide = showHintGuides,
                        strokes = tileStrokes[idx].orEmpty(),
                        isVerified = tileVerified[idx] == true,
                        lastGuess = tileLastGuess[idx],
                        onStrokesChanged = { updated -> tileStrokes[idx] = updated },
                        onEvaluate = { completedStrokes ->
                            scope.launch {
                                val res = LoreenStrokeRecognizer.recognize(completedStrokes)
                                tileLastGuess[idx] = res?.letter
                                val ok = LoreenStrokeRecognizer.matches(completedStrokes, expected)
                                tileVerified[idx] = ok
                                if (ok) {
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                }
                            }
                        },
                        onClear = {
                            tileStrokes[idx] = emptyList()
                            tileVerified[idx] = false
                            tileLastGuess[idx] = null
                        }
                    )
                }
            }

            if (allVerified) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(ThemeColors.accentGreen.copy(alpha = 0.14f))
                        .border(1.dp, ThemeColors.accentGreen.copy(alpha = 0.45f), RoundedCornerShape(16.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.Verified, contentDescription = null, tint = ThemeColors.accentGreen)
                        Column {
                            Text("Fluency Verified!", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            Text("Loreen Veil is ready to shield your Tagdos & Notes.", color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp)
                        }
                    }

                    Button(
                        onClick = onUnlocked,
                        colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentGreen),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Unlock & Enable Loreen Veil", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 14.5.sp)
                    }
                }
            } else {
                Text(
                    text = "Tip: Draw multi-stroke glyphs naturally (e.g., circle then cross for E). Recognition runs automatically 450ms after lifting your finger.",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 11.5.sp
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun ChallengeModePill(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) ThemeColors.accentCyan.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.06f))
            .border(1.dp, if (selected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.1f), RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.65f),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun AndroidLoreenDrawingTile(
    expectedLetter: Char,
    showHintGuide: Boolean,
    strokes: List<List<LoreenPoint>>,
    isVerified: Boolean,
    lastGuess: Char?,
    onStrokesChanged: (List<List<LoreenPoint>>) -> Unit,
    onEvaluate: (List<List<LoreenPoint>>) -> Unit,
    onClear: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var activeStroke by remember(expectedLetter) { mutableStateOf<List<LoreenPoint>>(emptyList()) }
    var debounceJob by remember(expectedLetter) { mutableStateOf<Job?>(null) }

    val borderColor = when {
        isVerified -> ThemeColors.accentGreen
        strokes.isNotEmpty() && lastGuess != null -> ThemeColors.accentOrange.copy(alpha = 0.7f)
        else -> Color.White.copy(alpha = 0.16f)
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Box(
            modifier = Modifier
                .size(104.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(if (isVerified) ThemeColors.accentGreen.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.05f))
                .border(if (isVerified) 2.dp else 1.dp, borderColor, RoundedCornerShape(16.dp))
        ) {
            if (showHintGuide) {
                Box(modifier = Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = expectedLetter.toString(),
                        fontFamily = LoreenFontFamily,
                        fontSize = 54.sp,
                        color = Color.White.copy(alpha = 0.12f)
                    )
                }
            }

            Canvas(
                modifier = Modifier
                    .matchParentSize()
                    .pointerInput(expectedLetter, strokes) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                debounceJob?.cancel()
                                activeStroke = listOf(LoreenPoint(offset.x.toDouble(), offset.y.toDouble()))
                            },
                            onDrag = { change, _ ->
                                change.consume()
                                val pt = LoreenPoint(change.position.x.toDouble(), change.position.y.toDouble())
                                activeStroke = activeStroke + pt
                            },
                            onDragEnd = {
                                val nextStrokes = if (activeStroke.isNotEmpty()) strokes + listOf(activeStroke) else strokes
                                activeStroke = emptyList()
                                onStrokesChanged(nextStrokes)
                                debounceJob?.cancel()
                                debounceJob = scope.launch {
                                    delay(450)
                                    onEvaluate(nextStrokes)
                                }
                            }
                        )
                    }
            ) {
                val path = Path()
                for (s in strokes) {
                    if (s.isNotEmpty()) {
                        path.moveTo(s[0].x.toFloat(), s[0].y.toFloat())
                        for (i in 1 until s.size) {
                            path.lineTo(s[i].x.toFloat(), s[i].y.toFloat())
                        }
                    }
                }
                if (activeStroke.isNotEmpty()) {
                    path.moveTo(activeStroke[0].x.toFloat(), activeStroke[0].y.toFloat())
                    for (i in 1 until activeStroke.size) {
                        path.lineTo(activeStroke[i].x.toFloat(), activeStroke[i].y.toFloat())
                    }
                }
                drawPath(
                    path = path,
                    color = if (isVerified) ThemeColors.accentGreen else ThemeColors.accentCyan,
                    style = Stroke(width = 10f, cap = StrokeCap.Round, join = StrokeJoin.Round)
                )
            }

            if (isVerified) {
                Icon(
                    imageVector = Icons.Rounded.CheckCircle,
                    contentDescription = "Verified",
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(16.dp)
                )
            } else if (strokes.isNotEmpty()) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Clear",
                    tint = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(16.dp)
                        .clickable {
                            debounceJob?.cancel()
                            activeStroke = emptyList()
                            onClear()
                        }
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = expectedLetter.toString(),
                color = if (isVerified) ThemeColors.accentGreen else Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
            )
            if (!isVerified && lastGuess != null) {
                Text("($lastGuess?)", color = ThemeColors.accentOrange, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun LoreenCodexSheet(onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var selectedTab by remember { mutableIntStateOf(0) }
    var practiceStrokes by remember { mutableStateOf<List<List<LoreenPoint>>>(emptyList()) }
    var activePracticeStroke by remember { mutableStateOf<List<LoreenPoint>>(emptyList()) }
    var practiceResult by remember { mutableStateOf<LoreenRecognitionResult?>(null) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF060D1A),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Loreen Codex", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                TextButton(onClick = onDismiss) {
                    Text("Done", color = ThemeColors.accentCyan, fontWeight = FontWeight.Bold)
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChallengeModePill("A–Z Codex", selectedTab == 0, { selectedTab = 0 }, Modifier.weight(1f))
                ChallengeModePill("Practice Pad", selectedTab == 1, { selectedTab = 1 }, Modifier.weight(1f))
                ChallengeModePill("How It Works", selectedTab == 2, { selectedTab = 2 }, Modifier.weight(1f))
            }

            when (selectedTab) {
                0 -> {
                    Text(
                        text = "Complete 26-letter Loreen Script reference. Cyan marks the 18 original recalled glyphs; purple marks the 8 pattern-completed glyphs.",
                        color = Color.White.copy(alpha = 0.68f),
                        fontSize = 12.sp
                    )
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        maxItemsInEachRow = 3
                    ) {
                        LoreenGlyphCatalog.allGlyphs.forEach { glyph ->
                            val isCompleted = glyph.origin == LoreenGlyphOrigin.COMPLETED
                            val accent = if (isCompleted) ThemeColors.accentPurple else ThemeColors.accentCyan
                            Column(
                                modifier = Modifier
                                    .width(102.dp)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color.White.copy(alpha = 0.05f))
                                    .border(1.dp, accent.copy(alpha = 0.28f), RoundedCornerShape(14.dp))
                                    .padding(10.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(glyph.id.toString(), color = accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(accent))
                                }
                                Text(
                                    text = glyph.id.toString(),
                                    fontFamily = LoreenFontFamily,
                                    fontSize = 34.sp,
                                    color = Color.White
                                )
                                Text(
                                    text = glyph.family,
                                    color = Color.White.copy(alpha = 0.52f),
                                    fontSize = 9.5.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
                1 -> {
                    Text(
                        text = "Draw any Loreen glyph below to test real-time offline recognition.",
                        color = Color.White.copy(alpha = 0.68f),
                        fontSize = 12.sp
                    )
                    Canvas(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(220.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(Color.White.copy(alpha = 0.05f))
                            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(18.dp))
                            .pointerInput(practiceStrokes) {
                                detectDragGestures(
                                    onDragStart = { offset ->
                                        activePracticeStroke = listOf(LoreenPoint(offset.x.toDouble(), offset.y.toDouble()))
                                    },
                                    onDrag = { change, _ ->
                                        change.consume()
                                        activePracticeStroke = activePracticeStroke + LoreenPoint(change.position.x.toDouble(), change.position.y.toDouble())
                                    },
                                    onDragEnd = {
                                        if (activePracticeStroke.isNotEmpty()) {
                                            val updated = practiceStrokes + listOf(activePracticeStroke)
                                            practiceStrokes = updated
                                            activePracticeStroke = emptyList()
                                            practiceResult = LoreenStrokeRecognizer.recognize(updated)
                                        }
                                    }
                                )
                            }
                    ) {
                        val path = Path()
                        for (s in practiceStrokes) {
                            if (s.isNotEmpty()) {
                                path.moveTo(s[0].x.toFloat(), s[0].y.toFloat())
                                for (i in 1 until s.size) path.lineTo(s[i].x.toFloat(), s[i].y.toFloat())
                            }
                        }
                        if (activePracticeStroke.isNotEmpty()) {
                            path.moveTo(activePracticeStroke[0].x.toFloat(), activePracticeStroke[0].y.toFloat())
                            for (i in 1 until activePracticeStroke.size) path.lineTo(activePracticeStroke[i].x.toFloat(), activePracticeStroke[i].y.toFloat())
                        }
                        drawPath(path, ThemeColors.accentCyan, style = Stroke(width = 12f, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val res = practiceResult
                        if (res != null) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(res.letter.toString(), fontFamily = LoreenFontFamily, fontSize = 28.sp, color = ThemeColors.accentCyan)
                                Column {
                                    Text("Recognized: ${res.letter}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                                    val alts = res.topCandidates.drop(1).take(3).joinToString(", ") { it.letter.toString() }
                                    if (alts.isNotEmpty()) {
                                        Text("Next closest: $alts", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp)
                                    }
                                }
                            }
                        } else {
                            Text("Draw a glyph above...", color = Color.White.copy(alpha = 0.5f), fontSize = 13.sp)
                        }

                        TextButton(onClick = {
                            practiceStrokes = emptyList()
                            activePracticeStroke = emptyList()
                            practiceResult = null
                        }) {
                            Text("Clear", color = ThemeColors.accentCyan, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                else -> {
                    LoreenDocItem(
                        icon = Icons.Rounded.VisibilityOff,
                        title = "What Loreen Veil Does",
                        body = "Loreen Veil renders your Tagdos pills, stream titles, active memos, and Quick Notes in Loreen Script — shielding personal thoughts from casual glances in public spaces."
                    )
                    LoreenDocItem(
                        icon = Icons.Rounded.TouchApp,
                        title = "Hold-to-Peek & Biometric Reveal",
                        body = "Press and hold the eye button in the Tagdos & Notes header to temporarily reveal readable Latin text with a sparkle decrypt sweep, then release to re-veil instantly."
                    )
                    LoreenDocItem(
                        icon = Icons.Rounded.Edit,
                        title = "Safe Editing & Zero Cloud Impact",
                        body = "Opening any pill editor, Raw DSL editor, or Markdown note editor automatically switches back to readable Latin. Underlying data stays standard UTF-8 in Room and Supabase with zero extra network egress."
                    )
                    LoreenDocItem(
                        icon = Icons.Rounded.Public,
                        title = "Romanian Diacritics & Monocase",
                        body = "Loreen maps Romanian diacritics inside the font itself (Ă/Â → A, Î → I, Ș → S, Ț → T), alongside geometric numerals and TagDoS DSL symbols (/, &, $, €, !)."
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun LoreenDocItem(
    icon: ImageVector,
    title: String,
    body: String
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, tint = ThemeColors.accentCyan, modifier = Modifier.size(16.dp))
            Text(title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
        Text(body, color = Color.White.copy(alpha = 0.75f), fontSize = 12.5.sp, lineHeight = 18.sp)
    }
}
