package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.SleepAIContext
import com.intellidream.daily.model.SleepSession
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val isUser: Boolean,
    val text: String
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SleepAICoachCard(
    aiContext: SleepAIContext,
    session: SleepSession,
    modifier: Modifier = Modifier
) {
    var showingChatSheet by remember { mutableStateOf(false) }
    var selectedPrompt by remember { mutableStateOf<String?>(null) }

    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Header with AI Sparkle Badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(13.dp)
                    )
                    Text(
                        text = "DAILY SLEEP INTELLIGENCE",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF00E676))
                    )
                    Text(
                        text = "AI Coach",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                }
            }

            // Conversational intro
            Text(
                text = "Analyzing your ${session.totalAsleepFormatted} of sleep architecture against your personal circadian baseline:",
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.9f)
            )

            // Suggested Question Chips
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "SUGGESTED QUESTIONS",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.fgMutedDark
                )

                aiContext.suggestedPrompts.forEach { prompt ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.White.copy(alpha = 0.05f))
                            .clickable {
                                selectedPrompt = prompt
                                showingChatSheet = true
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ChatBubble,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(11.dp)
                        )
                        Text(
                            text = prompt,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White,
                            modifier = Modifier.weight(1f)
                        )
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = null,
                            tint = ThemeColors.fgMutedDark,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }

            // Ask AI Button
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(ThemeColors.accentCyan, Color(0xFF80D8FF))
                        )
                    )
                    .clickable {
                        selectedPrompt = null
                        showingChatSheet = true
                    }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = Color.Black,
                        modifier = Modifier.size(14.dp)
                    )
                    Text(
                        text = "Ask Sleep AI a Question...",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                }
            }
        }
    }

    if (showingChatSheet) {
        SleepAIChatBottomSheet(
            session = session,
            initialPrompt = selectedPrompt,
            onDismiss = { showingChatSheet = false }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SleepAIChatBottomSheet(
    session: SleepSession,
    initialPrompt: String?,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val messages = remember { mutableStateListOf<ChatMessage>() }
    var userQuery by remember { mutableStateOf("") }
    var isGenerating by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        val initialGreeting = "Hello! I am your Daily Sleep Intelligence assistant. I have reviewed your latest session: ${session.totalAsleepFormatted} of total sleep with ${session.deepFormatted} of Deep sleep and ${session.remFormatted} of REM sleep. How can I help optimize your recovery today?"
        messages.add(ChatMessage(isUser = false, text = initialGreeting))

        if (!initialPrompt.isNullOrEmpty()) {
            userQuery = initialPrompt
            messages.add(ChatMessage(isUser = true, text = initialPrompt))
            userQuery = ""
            isGenerating = true
            delay(600)
            isGenerating = false
            val response = generateResponse(initialPrompt, session)
            messages.add(ChatMessage(isUser = false, text = response))
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF0D1A35)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxSize(0.9f)
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
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
                        text = "Sleep Intelligence",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }

                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "Close",
                        tint = Color.White.copy(alpha = 0.7f)
                    )
                }
            }

            // Message list
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(messages, key = { it.id }) { msg ->
                    if (msg.isUser) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(ThemeColors.accentBlue)
                                    .padding(horizontal = 14.dp, vertical = 10.dp)
                            ) {
                                Text(
                                    text = msg.text,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color.White
                                )
                            }
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Start
                        ) {
                            Row(
                                verticalAlignment = Alignment.Top,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.AutoAwesome,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier
                                        .padding(top = 2.dp)
                                        .size(14.dp)
                                )
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(Color.White.copy(alpha = 0.08f))
                                        .padding(horizontal = 14.dp, vertical = 10.dp)
                                ) {
                                    Text(
                                        text = msg.text,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Normal,
                                        color = Color.White.copy(alpha = 0.95f),
                                        lineHeight = 20.sp
                                    )
                                }
                            }
                        }
                    }
                }

                if (isGenerating) {
                    item {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(start = 8.dp)
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                color = ThemeColors.accentCyan,
                                strokeWidth = 2.dp
                            )
                            Text(
                                text = "Analyzing sleep architecture...",
                                fontSize = 12.sp,
                                color = ThemeColors.fgMutedDark
                            )
                        }
                    }
                }
            }

            // Input Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = userQuery,
                    onValueChange = { userQuery = it },
                    placeholder = { Text("Ask anything about your sleep...", color = ThemeColors.fgMutedDark, fontSize = 14.sp) },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(20.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.White.copy(alpha = 0.08f),
                        unfocusedContainerColor = Color.White.copy(alpha = 0.08f),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    ),
                    singleLine = true
                )

                IconButton(
                    onClick = {
                        val q = userQuery.trim()
                        if (q.isNotEmpty()) {
                            messages.add(ChatMessage(isUser = true, text = q))
                            userQuery = ""
                            isGenerating = true
                            scope.launch {
                                delay(600)
                                isGenerating = false
                                val ans = generateResponse(q, session)
                                messages.add(ChatMessage(isUser = false, text = ans))
                            }
                        }
                    },
                    enabled = userQuery.trim().isNotEmpty()
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.Send,
                        contentDescription = "Send",
                        tint = if (userQuery.trim().isNotEmpty()) ThemeColors.accentCyan else Color.White.copy(alpha = 0.3f),
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
        }
    }
}

private fun generateResponse(query: String, session: SleepSession): String {
    val q = query.lowercase()
    val deepPct = session.deepPercent
    val remPct = session.remPercent
    val effPct = session.efficiencyPercent

    return when {
        q.contains("deep") || q.contains("profund") -> {
            "Azi-noapte ai înregistrat ${session.deepFormatted} de Deep Sleep ($deepPct% din totalul somnului). Intervalul clinic recomandat este între 15% și 25%. Somnul profund este crucial pentru secreția hormonului de creștere și refacerea musculară. Pentru a-l crește diseară, păstrează dormitorul răcoros (18-20°C) și evită alimentele bogate în carbohidrați simpli cu 3 ore înainte de culcare."
        }
        q.contains("antrenament") || q.contains("cardio") || q.contains("effort") || q.contains("intens") -> {
            if (session.sleepScore >= 75) {
                "Cu un scor de somn de ${session.sleepScore} și o eficiență de $effPct%, sistemul tău nervos central și tonusul vagal sunt bine refăcute. Ești într-o stare optimă pentru un antrenament cu intensitate medie sau ridicată astăzi. Nu uita să te hidratezi bine!"
            } else {
                "Scorul tău de somn a fost moderat (${session.sleepScore}). Ținând cont de acumularea de oboseală, este recomandat să eviți un antrenament maximal sau cardio de mare intensitate. O sesiune de recuperare activă (mers alert 30 min, mobilitate sau stretching) va ajuta la refacere fără să suprasolicite sistemul cardiovascular."
            }
        }
        q.contains("rem") || q.contains("vis") -> {
            "Somnul tău REM a fost de ${session.remFormatted} ($remPct% din somn). Stadiul REM este esențial pentru consolidarea memoriei, procesarea emoțiilor și claritatea mentală. Alcoolul și mesele copioase de seară suprimă masiv prima jumătate a somnului REM. Pentru o refacere cognitivă superioară, încearcă o rutină de 10 minute de citit înainte de culcare fără ecrane."
        }
        q.contains("trezir") || q.contains("awake") -> {
            "Ai înregistrat ${session.awakeCount} treziri nocturne (în total ${session.awakeFormatted} de stare trează). Trezirile scurte (sub 3 minute) sunt fiziologice între ciclurile de 90 de minute, dar trezirile prelungite pot indica o temperatură ambientală prea ridicată, lumină ambientală sau fluctuații de cortizol/glicemie. Încearcă să nu bei cantități mari de apă în ultima oră înainte de somn."
        }
        else -> {
            "Pe baza datelor din noaptea precedentă (${session.totalAsleepFormatted} somn efectiv, $effPct% eficiență, ${session.restorativePercent}% stadii regenerative), corpul tău prezintă o curbă bună de refacere. Pentru a-ți menține ritmul circadian stabil, expune-te la lumină naturală în prima oră a dimineții și păstrează o oră de culcare consecventă."
        }
    }
}
