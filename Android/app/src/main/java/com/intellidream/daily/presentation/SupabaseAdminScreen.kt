package com.intellidream.daily.presentation

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.SupabaseAdminSnapshot
import com.intellidream.daily.model.SupabaseDailyEgressPoint
import com.intellidream.daily.network.SupabaseAdminRepository
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class AdminFilterTab(val label: String) {
    ALL("All Telemetry"),
    QUOTAS("Quotas & Egress"),
    DATABASE("Database & Bloat"),
    GATEWAY("Gateway & Logs"),
    RUNTIME("Functions & Realtime"),
    FLEET("Fleet & Advisors")
}

@Composable
fun SupabaseAdminScreen(
    geminiApiKey: String?,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val repo = remember {
        SupabaseAdminRepository.shared.also { it.initializeIfNeeded(context) }
    }
    val scope = rememberCoroutineScope()

    val creds by repo.credentials.collectAsState()
    val snapshot by repo.snapshot.collectAsState()
    val isLoading by repo.isLoading.collectAsState()
    val isAnalyzingAi by repo.isAnalyzingAi.collectAsState()
    val aiAnalysis by repo.aiAnalysis.collectAsState()
    val errorMsg by repo.errorMessage.collectAsState()

    var activeTab by remember { mutableStateOf(AdminFilterTab.ALL) }
    var feedbackToast by remember { mutableStateOf<String?>(null) }
    var showProjectMenu by remember { mutableStateOf(false) }

    val config = LocalConfiguration.current
    val isWide = config.screenWidthDp >= 600 // Foldable Galaxy Z Fold 8 ("Radar") / tablet

    LaunchedEffect(Unit) {
        repo.ensureLoadedOnAppear()
    }

    val onDismissWithLock = {
        repo.lock()
        onDismiss()
    }

    DisposableEffect(Unit) {
        onDispose {
            repo.lock()
        }
    }

    BackHandler { onDismissWithLock() }

    Dialog(
        onDismissRequest = onDismissWithLock,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(ThemeColors.backgroundGradient)
                .statusBarsPadding()
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.36f))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Storage,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(22.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = snapshot?.project?.name ?: "Supabase Cloud Console",
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        snapshot?.let { snap ->
                            Text(
                                text = snap.orgPlan.uppercase(Locale.US),
                                color = Color.Black,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.ExtraBold,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(ThemeColors.accentCyan)
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                        Text(
                            text = "READ-ONLY",
                            color = ThemeColors.success,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(ThemeColors.success.copy(alpha = 0.14f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }

                    val subText = remember(snapshot?.fetchedAtEpochMs, creds.adminIdentity, feedbackToast) {
                        feedbackToast ?: buildString {
                            creds.adminIdentity?.let { append("$it · ") }
                            snapshot?.let { s ->
                                val tf = SimpleDateFormat("HH:mm:ss", Locale.US)
                                append("${s.computeTier} · ${s.project.region} · ${tf.format(Date(s.fetchedAtEpochMs))}")
                            } ?: append("10-min cached cloud telemetry")
                        }
                    }
                    Text(
                        text = subText,
                        color = if (feedbackToast != null) ThemeColors.success else ThemeColors.fgMutedDark,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Multi-project selector if > 1
                val projects = snapshot?.availableProjects.orEmpty()
                if (projects.size > 1) {
                    Box {
                        Text(
                            text = "Projects",
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.08f))
                                .clickable { showProjectMenu = true }
                                .padding(horizontal = 10.dp, vertical = 6.dp)
                        )
                        DropdownMenu(expanded = showProjectMenu, onDismissRequest = { showProjectMenu = false }) {
                            projects.forEach { p ->
                                DropdownMenuItem(
                                    text = { Text("${p.name} (${p.ref})") },
                                    onClick = {
                                        showProjectMenu = false
                                        scope.launch { repo.selectProject(p.ref) }
                                    }
                                )
                            }
                        }
                    }
                }

                // Copy Markdown
                IconButton(
                    enabled = snapshot != null,
                    onClick = {
                        snapshot?.toMarkdownReport()?.let { md ->
                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cm.setPrimaryClip(ClipData.newPlainText("Supabase Forensic Report", md))
                            feedbackToast = "Forensic Markdown copied!"
                        }
                    }
                ) {
                    Icon(Icons.Rounded.ContentCopy, contentDescription = "Copy Markdown", tint = Color.White)
                }

                // Share Markdown
                IconButton(
                    enabled = snapshot != null,
                    onClick = {
                        snapshot?.toMarkdownReport()?.let { md ->
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/markdown"
                                putExtra(Intent.EXTRA_SUBJECT, "Supabase Cloud Forensic Telemetry")
                                putExtra(Intent.EXTRA_TEXT, md)
                            }
                            context.startActivity(Intent.createChooser(sendIntent, "Export Telemetry Report"))
                        }
                    }
                ) {
                    Icon(Icons.Rounded.Share, contentDescription = "Share Report", tint = Color.White)
                }

                // Refresh
                IconButton(
                    enabled = !isLoading,
                    onClick = { scope.launch { repo.refreshSnapshot(force = true) } }
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            color = ThemeColors.accentCyan,
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(Icons.Rounded.Refresh, contentDescription = "Refresh", tint = ThemeColors.accentCyan)
                    }
                }

                // Disconnect
                IconButton(
                    onClick = {
                        repo.disconnect()
                        onDismissWithLock()
                    }
                ) {
                    Icon(Icons.AutoMirrored.Rounded.Logout, contentDescription = "Disconnect", tint = ThemeColors.error)
                }

                IconButton(onClick = onDismissWithLock) {
                    Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = if (isWide) 24.dp else 16.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                if (!errorMsg.isNullOrBlank()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(ThemeColors.error.copy(alpha = 0.18f))
                                .padding(12.dp)
                        ) {
                            Text(text = errorMsg.orEmpty(), color = Color.White, fontSize = 12.sp)
                        }
                    }
                }

                val snap = snapshot
                if (snap == null) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 80.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                CircularProgressIndicator(color = ThemeColors.accentCyan)
                                Spacer(Modifier.height(12.dp))
                                Text(
                                    text = "Fetching Supabase Quotas, ClickHouse Logs & pg_catalog...",
                                    color = ThemeColors.fgMutedDark,
                                    fontSize = 13.sp
                                )
                            }
                        }
                    }
                } else {
                    // Service Health Strip
                    if (snap.serviceHealth.isNotEmpty()) {
                        item {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                snap.serviceHealth.forEach { svc ->
                                    Row(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(Color.White.copy(alpha = 0.07f))
                                            .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                                            .padding(horizontal = 10.dp, vertical = 5.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(7.dp)
                                                .clip(CircleShape)
                                                .background(if (svc.healthy) ThemeColors.success else ThemeColors.error)
                                        )
                                        Text(svc.displayName, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }
                        }
                    }

                    // AI SRE Co-Pilot Card
                    item {
                        GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.AutoAwesome,
                                            contentDescription = null,
                                            tint = ThemeColors.accentCyan,
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Text(
                                            text = "Cloud SRE AI Co-Pilot",
                                            color = ThemeColors.accentCyan,
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }

                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(ThemeColors.accentCyan)
                                            .clickable(enabled = !isAnalyzingAi) {
                                                scope.launch { repo.analyzeWithAi(geminiApiKey) }
                                            }
                                            .padding(horizontal = 12.dp, vertical = 6.dp)
                                    ) {
                                        Text(
                                            text = if (isAnalyzingAi) "Analyzing..." else if (aiAnalysis == null) "Analyze with AI" else "Refresh AI",
                                            color = Color.Black,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }

                                Text(
                                    text = aiAnalysis
                                        ?: "Synthesize Unified Egress drivers, PostgreSQL B-tree index bloat, Realtime WAL CPU, and Advisor lints.",
                                    color = if (aiAnalysis != null) Color.White else ThemeColors.fgMutedDark,
                                    fontSize = 12.sp,
                                    lineHeight = 18.sp
                                )
                            }
                        }
                    }

                    // Filter Tabs
                    item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            AdminFilterTab.entries.forEach { tab ->
                                val selected = activeTab == tab
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(if (selected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.08f))
                                        .clickable { activeTab = tab }
                                        .padding(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text(
                                        text = tab.label,
                                        color = if (selected) Color.Black else Color.White,
                                        fontSize = 12.sp,
                                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium
                                    )
                                }
                            }
                        }
                    }

                    // 1. Quotas & Stacked Daily Egress
                    if (activeTab == AdminFilterTab.ALL || activeTab == AdminFilterTab.QUOTAS) {
                        item {
                            ExecutiveQuotaSection(snap = snap, isWide = isWide)
                        }
                        if (snap.dailyEgress.isNotEmpty()) {
                            item {
                                DailyStackedEgressCard(points = snap.dailyEgress)
                            }
                        }
                    }

                    // 2. Database & Index Bloat
                    if (activeTab == AdminFilterTab.ALL || activeTab == AdminFilterTab.DATABASE) {
                        item {
                            DatabaseForensicsCard(snap = snap)
                        }
                    }

                    // 3. ClickHouse Logs & Gateway Routes
                    if (activeTab == AdminFilterTab.ALL || activeTab == AdminFilterTab.GATEWAY) {
                        item {
                            GatewayRoutesCard(snap = snap)
                        }
                    }

                    // 4. Edge Functions & Realtime WAL
                    if (activeTab == AdminFilterTab.ALL || activeTab == AdminFilterTab.RUNTIME) {
                        item {
                            RuntimeFunctionsRealtimeCard(snap = snap)
                        }
                    }

                    // 5. Ecosystem Fleet & Advisors
                    if (activeTab == AdminFilterTab.ALL || activeTab == AdminFilterTab.FLEET) {
                        item {
                            FleetAndAdvisorsCard(snap = snap)
                        }
                    }

                    // 6. Console Security & Biometric Lock
                    item {
                        ConsoleSecurityCard(
                            requireBiometrics = creds.requireBiometrics,
                            onToggleBiometrics = { target ->
                                val act = BiometricAuthHelper.getActivity(context)
                                if (act != null && BiometricAuthHelper.isBiometricAvailable(act)) {
                                    BiometricAuthHelper.prompt(
                                        activity = act,
                                        title = if (target) "Enable Biometric Protection" else "Disable Biometric Protection",
                                        subtitle = "Authenticate to update Supabase Admin console security",
                                        onSuccess = {
                                            repo.setRequireBiometrics(target)
                                            feedbackToast = if (target) "Biometric Lock Enabled" else "Biometric Lock Disabled"
                                        },
                                        onError = { err ->
                                            feedbackToast = "Auth cancelled: $err"
                                        }
                                    )
                                } else {
                                    repo.setRequireBiometrics(target)
                                    feedbackToast = if (target) "Biometrics required" else "Biometrics disabled"
                                }
                            }
                        )
                    }
                }

                item {
                    Spacer(Modifier.height(24.dp).navigationBarsPadding())
                }
            }
        }
    }
}

@Composable
private fun BillingCycleEgressCard(snap: SupabaseAdminSnapshot) {
    val percent = snap.egressCycleQuotaPercent
    val accent = when {
        percent >= 95.0 -> ThemeColors.error
        percent >= 78.0 -> ThemeColors.warning
        else -> ThemeColors.accentCyan
    }
    val cycleUsed = remember(snap.egressCycleUsedBytes) { SupabaseAdminSnapshot.formatBytes(snap.egressCycleUsedBytes) }
    val cycleQuota = remember(snap.egressCycleQuotaBytes) { SupabaseAdminSnapshot.formatBytes(snap.egressCycleQuotaBytes) }
    val egress24h = remember(snap.egress24hBytes) { SupabaseAdminSnapshot.formatBytes(snap.egress24hBytes) }
    val cachedEgress = remember(snap.cachedEgressUsedBytes) { SupabaseAdminSnapshot.formatBytes(snap.cachedEgressUsedBytes) }

    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Sync,
                            contentDescription = null,
                            tint = accent,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "Unified Egress · Billing Cycle",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Text(
                        text = if (snap.isExactBillingUsageAvailable) "Current Billing Month · Invoiced Bandwidth" else "Rolling 30-Day Aggregation",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 11.sp
                    )
                }

                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(accent.copy(alpha = 0.16f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = String.format(Locale.US, "%.1f%%", percent),
                        color = accent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }

            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = cycleUsed,
                    color = Color.White,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "/ $cycleQuota",
                    color = ThemeColors.textMuted,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(bottom = 3.dp)
                )
            }

            // Progress bar
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(7.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.10f))
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(fraction = (percent / 100.0).coerceIn(0.02, 1.0).toFloat())
                        .fillMaxHeight()
                        .clip(CircleShape)
                        .background(
                            Brush.horizontalGradient(
                                listOf(accent, accent.copy(alpha = 0.75f))
                            )
                        )
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text = "Gateway 24h:", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    Text(text = egress24h, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                }
                if (snap.cachedEgressUsedBytes > 0L) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(text = "Cached CDN:", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        Text(text = cachedEgress, color = ThemeColors.accentCyan, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(text = "Requests:", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        Text(text = "${snap.totalHttpRequests24h}", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

@Composable
private fun ExecutiveQuotaSection(snap: SupabaseAdminSnapshot, isWide: Boolean) {
    val h24Used = remember(snap.egress24hBytes) { SupabaseAdminSnapshot.formatBytes(snap.egress24hBytes) }
    val dbUsed = remember(snap.dbSizeBytes) { SupabaseAdminSnapshot.formatBytes(snap.dbSizeBytes) }
    val dbQuota = remember(snap.dbQuotaBytes) { SupabaseAdminSnapshot.formatBytes(snap.dbQuotaBytes) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        BillingCycleEgressCard(snap = snap)

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            QuotaGaugeTile(
                modifier = Modifier.weight(1f),
                title = "Gateway Egress (24h)",
                used = h24Used,
                quota = "${snap.totalHttpRequests24h} reqs",
                percent = snap.egress24hQuotaPercent,
                sub = if (snap.cachedEgressUsedBytes > 0) "CDN: ${SupabaseAdminSnapshot.formatBytes(snap.cachedEgressUsedBytes)}" else "24h HTTP: ${snap.totalHttpRequests24h}"
            )
            QuotaGaugeTile(
                modifier = Modifier.weight(1f),
                title = "Database Size",
                used = dbUsed,
                quota = dbQuota,
                percent = snap.dbQuotaPercent,
                sub = "Cache Hit ${String.format(Locale.US, "%.1f%%", snap.cacheHitRatioPercent)}"
            )
            if (isWide) {
                QuotaGaugeTile(
                    modifier = Modifier.weight(1f),
                    title = "Edge Calls",
                    used = "${snap.functionInvocations}",
                    quota = "${snap.functionInvocationsQuota}",
                    percent = if (snap.functionInvocationsQuota > 0) snap.functionInvocations * 100.0 / snap.functionInvocationsQuota else 0.0,
                    sub = "${snap.edgeFunctions.size} functions"
                )
                QuotaGaugeTile(
                    modifier = Modifier.weight(1f),
                    title = "Realtime & MAU",
                    used = "${snap.realtimeActiveSubscriptions} subs",
                    quota = "Peak ${snap.realtimePeakConnections}",
                    percent = if (snap.realtimePeakConnectionsQuota > 0) snap.realtimePeakConnections * 100.0 / snap.realtimePeakConnectionsQuota else 0.0,
                    sub = "MAU: ${snap.mauCount}"
                )
            }
        }
        if (!isWide) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                QuotaGaugeTile(
                    modifier = Modifier.weight(1f),
                    title = "Edge Calls",
                    used = "${snap.functionInvocations}",
                    quota = "${snap.functionInvocationsQuota}",
                    percent = if (snap.functionInvocationsQuota > 0) snap.functionInvocations * 100.0 / snap.functionInvocationsQuota else 0.0,
                    sub = "${snap.edgeFunctions.size} functions"
                )
                QuotaGaugeTile(
                    modifier = Modifier.weight(1f),
                    title = "Realtime & MAU",
                    used = "${snap.realtimeActiveSubscriptions} subs",
                    quota = "Peak ${snap.realtimePeakConnections}",
                    percent = if (snap.realtimePeakConnectionsQuota > 0) snap.realtimePeakConnections * 100.0 / snap.realtimePeakConnectionsQuota else 0.0,
                    sub = "MAU: ${snap.mauCount}"
                )
            }
        }
    }
}

@Composable
private fun QuotaGaugeTile(
    modifier: Modifier,
    title: String,
    used: String,
    quota: String,
    percent: Double,
    sub: String
) {
    val accent = when {
        percent >= 95.0 -> ThemeColors.error
        percent >= 78.0 -> ThemeColors.warning
        else -> ThemeColors.accentCyan
    }
    val pctText = remember(percent) { String.format(Locale.US, "%.1f%%", percent) }

    GlassCard(modifier = modifier, cornerRadius = 16.dp, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title, color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text(pctText, color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            }
            Text(used, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("/ $quota", color = ThemeColors.textMuted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(5.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.10f))
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(fraction = (percent / 100.0).toFloat().coerceIn(0.03f, 1f))
                        .clip(CircleShape)
                        .background(accent)
                )
            }
            Text(sub, color = ThemeColors.fgMutedDark, fontSize = 10.sp, maxLines = 1)
        }
    }
}

@Composable
private fun DailyStackedEgressCard(points: List<SupabaseDailyEgressPoint>) {
    val recent = remember(points) { points.takeLast(14) }
    val maxTotal = remember(recent) { maxOf(1L, recent.maxOfOrNull { it.totalBytes } ?: 1L) }

    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Daily Stacked Egress (PostgREST · Edge · Realtime · Storage)", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Canvas(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(130.dp)
            ) {
                val count = recent.size
                if (count == 0) return@Canvas
                val slotW = size.width / count
                val barW = (slotW * 0.62f).coerceAtLeast(6f)

                recent.forEachIndexed { i, pt ->
                    val x = i * slotW + (slotW - barW) / 2f
                    var currentBottom = size.height
                    val segments = listOf(
                        pt.restBytes to ThemeColors.accentCyan,
                        pt.functionBytes to ThemeColors.accentPurple,
                        pt.realtimeBytes to ThemeColors.accentGreen,
                        (pt.authBytes + pt.storageBytes + pt.supavisorBytes) to ThemeColors.accentBlue
                    )
                    segments.forEach { (bytes, col) ->
                        if (bytes > 0L) {
                            val h = (bytes.toFloat() / maxTotal.toFloat()) * (size.height - 8f)
                            drawRoundRect(
                                color = col,
                                topLeft = Offset(x, currentBottom - h),
                                size = Size(barW, h),
                                cornerRadius = CornerRadius(4f, 4f)
                            )
                            currentBottom -= h
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DatabaseForensicsCard(snap: SupabaseAdminSnapshot) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("PostgreSQL Tables & B-Tree Index Bloat", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Text("Conns: ${snap.activeDbConnections} · IOPS: ${snap.diskIops}", color = ThemeColors.accentCyan, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            }
            snap.tables.take(14).forEach { tbl ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "${tbl.schema}.${tbl.tableName}",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "Heap ${SupabaseAdminSnapshot.formatBytes(tbl.dataBytes)} · Idx ${SupabaseAdminSnapshot.formatBytes(tbl.indexBytes)} · Live ${tbl.liveRows}",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (tbl.hasIndexBloatWarning) {
                            Text(
                                text = "Bloat ${String.format(Locale.US, "%.1fx", tbl.bloatRatio)}",
                                color = ThemeColors.warning,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(ThemeColors.warning.copy(alpha = 0.16f))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                        Text(
                            text = SupabaseAdminSnapshot.formatBytes(tbl.totalBytes),
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                }
            }
            if (snap.cronJobs.isNotEmpty()) {
                HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
                Text("pg_cron Retention Jobs", color = ThemeColors.accentCyan, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                snap.cronJobs.forEach { j ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(j.jobName, color = Color.White, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        Text("${j.schedule} · ${j.status}", color = if (j.isSucceeded || j.status == "scheduled") ThemeColors.success else ThemeColors.error, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

@Composable
private fun GatewayRoutesCard(snap: SupabaseAdminSnapshot) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Top 24h HTTP Gateway Routes", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Text("2xx: ${snap.http2xxCount24h} · 4xx: ${snap.http4xxCount24h} · 5xx: ${snap.http5xxCount24h}", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            }
            snap.topRoutes24h.take(10).forEach { r ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        text = "${r.method} ${r.path}",
                        color = Color.White,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "${r.requests24h} req · ${SupabaseAdminSnapshot.formatBytes(r.responseBytes24h)}",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}

@Composable
private fun RuntimeFunctionsRealtimeCard(snap: SupabaseAdminSnapshot) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Edge Functions & Realtime Elixir", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text(
                text = "Realtime list_changes WAL CPU: ${String.format(Locale.US, "%.1f%%", snap.realtimeWalCpuSharePercent)} (${snap.realtimeActiveSubscriptions} active subs)",
                color = ThemeColors.accentCyan,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
            snap.edgeFunctions.forEach { fn ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("${fn.slug} (v${fn.version})", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                    Text("${fn.invocations24h} calls · ${String.format(Locale.US, "%.0f ms", fn.avgExecutionMs)}", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

@Composable
private fun FleetAndAdvisorsCard(snap: SupabaseAdminSnapshot) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("DayOne Ecosystem Fleet & Advisors", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            snap.fleetDevices.forEach { dev ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(dev.displayName, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    Text("${dev.requests24h} req (${String.format(Locale.US, "%.0f%%", dev.sharePercent)})", color = ThemeColors.fgMutedDark, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                }
            }
            val lints = snap.securityLints + snap.performanceLints
            if (lints.isNotEmpty()) {
                HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
                lints.take(6).forEach { lint ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = "[${lint.category} · ${lint.level}] ${lint.title}",
                            color = if (lint.level == "ERROR") ThemeColors.error else ThemeColors.warning,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(lint.detail, color = ThemeColors.fgMutedDark, fontSize = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun ConsoleSecurityCard(
    requireBiometrics: Boolean,
    onToggleBiometrics: (Boolean) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, padding = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Fingerprint,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "Require Biometric Lock",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Switch(
                    checked = requireBiometrics,
                    onCheckedChange = { onToggleBiometrics(it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = ThemeColors.accentCyan,
                        uncheckedThumbColor = Color.LightGray,
                        uncheckedTrackColor = Color.White.copy(alpha = 0.12f)
                    )
                )
            }

            Text(
                text = "Require Fingerprint, Face, or device credential each time the Supabase Admin Console is opened to safeguard database and API telemetry.",
                color = ThemeColors.fgMutedDark,
                fontSize = 12.sp,
                lineHeight = 16.sp
            )
        }
    }
}
