package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.model.ParsedSmartLedger

class DailyMoneyGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val parsedLedger = app?.smartLedgerRepository?.parsedLedger?.value

        provideContent {
            MoneyWidgetContent(
                context = context,
                ledger = parsedLedger
            )
        }
    }

    @Composable
    private fun MoneyWidgetContent(
        context: Context,
        ledger: ParsedSmartLedger?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_FINANCES)
        }

        val netWorth = ledger?.netWorth ?: 0.0
        val netWorthEUR = ledger?.formattedNetWorthEUR ?: "~0 €"
        val formattedNetWorth = ledger?.formattedBadge(netWorth) ?: "0 Lei"
        val incoming = ledger?.incomingTotal ?: 0.0
        val outgoing = ledger?.outgoingTotal ?: 0.0

        val accentGreen = Color(0xFF00E676)
        val accentBlue = Color(0xFF3B82F6)
        val accentOrange = Color(0xFFFF7043)

        // Find top 2 outgoing expense items
        val outgoingSection = ledger?.sections?.firstOrNull { it.name.equals("Outgoing", ignoreCase = true) }
        val topItems = outgoingSection?.items
            ?.filter { !it.isPureNote && it.rawAmount > 0 }
            ?.sortedByDescending { it.rawAmount }
            ?.take(2)
            ?: emptyList()

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF07141C))
                .padding(14.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Header Row
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "💳 SMART LEDGER",
                        style = TextStyle(
                            color = ColorProvider(accentGreen),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(accentGreen.copy(alpha = 0.18f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = netWorthEUR,
                            style = TextStyle(
                                color = ColorProvider(accentGreen),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Net Worth Display
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = formattedNetWorth,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 26.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Cash Flow Row: In vs Out
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "In: +${incoming.toInt()}k",
                        style = TextStyle(
                            color = ColorProvider(accentBlue),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(12.dp))
                    Text(
                        text = "Out: -${outgoing.toInt()}k",
                        style = TextStyle(
                            color = ColorProvider(accentOrange),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(6.dp))

                // Footer top spending allocations
                val subtitle = if (topItems.isNotEmpty()) {
                    topItems.joinToString(" · ") { "${it.displayName}: ${it.formattedRawAmount}" }
                } else {
                    "Tap to edit ledger & allocate budget"
                }

                Text(
                    text = subtitle,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF8E9BAE)),
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    maxLines = 1
                )
            }
        }
    }
}

class DailyMoneyGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyMoneyGlanceWidget()
}
