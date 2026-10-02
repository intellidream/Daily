package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
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
import java.util.Locale
import kotlin.math.abs

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
        val incoming = ledger?.incomingTotal ?: 0.0
        val outgoing = ledger?.outgoingTotal ?: 0.0

        val allItems = ledger?.sections?.flatMap { it.items } ?: emptyList()
        val cardItem = allItems.firstOrNull { it.displayName.contains("Card", ignoreCase = true) || it.key.contains("Card", ignoreCase = true) }
        val cashItem = allItems.firstOrNull { it.displayName.contains("Cash", ignoreCase = true) || it.key.contains("Cash", ignoreCase = true) }
        val cardAmt = cardItem?.calculatedAmount ?: 0.0
        val cashAmt = cashItem?.calculatedAmount ?: 0.0

        val accentGreen = Color(0xFF00E676)
        val accentCyan = Color(0xFF00E5FF)
        val accentPink = Color(0xFFF43F5E)
        val textMuted = Color(0xFF8E9BAE)
        val dividerColor = Color.White.copy(alpha = 0.12f)

        fun formatCompact(v: Double): String {
            val a = abs(v)
            return when {
                a >= 1_000_000 -> String.format(Locale.US, "%.1fM", v / 1_000_000.0)
                a >= 1000 -> String.format(Locale.US, "%.1fk", v / 1000.0)
                else -> String.format(Locale.US, "%.0f", v)
            }
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF071418))
                .padding(12.dp)
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Header: Wallet icon on left, EUR badge on right
                Row(
                    modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(launchIntent)),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(text = "👛", style = TextStyle(fontSize = 13.sp))
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "SMART LEDGER",
                            style = TextStyle(
                                color = ColorProvider(accentGreen),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(10.dp)
                            .background(accentCyan.copy(alpha = 0.16f))
                            .padding(horizontal = 7.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = netWorthEUR,
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // 3 Columns: NET WORTH | FLOW (IN/OUT) | LIQUID (Matches iOS 1:1)
                Row(
                    modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(launchIntent)),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Column 1: NET WORTH
                    Column(
                        modifier = GlanceModifier.defaultWeight(),
                        horizontalAlignment = Alignment.Start
                    ) {
                        Text(
                            text = "NET WORTH",
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 7.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(1.dp))
                        Text(
                            text = "${formatCompact(netWorth)} Lei",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                    }

                    // Vertical Divider 1
                    Box(
                        modifier = GlanceModifier
                            .width(1.dp)
                            .height(26.dp)
                            .background(dividerColor)
                    ) {}

                    Spacer(modifier = GlanceModifier.width(6.dp))

                    // Column 2: FLOW (IN/OUT)
                    Column(
                        modifier = GlanceModifier.defaultWeight(),
                        horizontalAlignment = Alignment.Start
                    ) {
                        Text(
                            text = "FLOW (IN/OUT)",
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 7.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(1.dp))
                        Text(
                            text = "+${formatCompact(incoming)} / -${formatCompact(outgoing)}",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 10.5.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                    }

                    Spacer(modifier = GlanceModifier.width(6.dp))

                    // Vertical Divider 2
                    Box(
                        modifier = GlanceModifier
                            .width(1.dp)
                            .height(26.dp)
                            .background(dividerColor)
                    ) {}

                    Spacer(modifier = GlanceModifier.width(6.dp))

                    // Column 3: LIQUID
                    Column(
                        modifier = GlanceModifier.defaultWeight(),
                        horizontalAlignment = Alignment.Start
                    ) {
                        Text(
                            text = "LIQUID",
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 7.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(1.dp))
                        Text(
                            text = "Crd ${formatCompact(cardAmt)} · Csh ${formatCompact(cashAmt)}",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(10.dp))

                // 3 Smart Interactive Quick Adjust Buttons (Matches iOS 1:1)
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // -100 Crd
                    AdjustButtonPill(
                        label = "-100 Crd",
                        textColor = accentPink,
                        bgColor = accentPink.copy(alpha = 0.16f),
                        modifier = GlanceModifier.defaultWeight().height(26.dp)
                            .clickable(
                                actionRunCallback<AdjustLedgerActionCallback>(
                                    actionParametersOf(
                                        AdjustLedgerActionCallback.AccountKey to "Card",
                                        AdjustLedgerActionCallback.DeltaKey to -100.0
                                    )
                                )
                            )
                    )

                    Spacer(modifier = GlanceModifier.width(6.dp))

                    // -100 Csh
                    AdjustButtonPill(
                        label = "-100 Csh",
                        textColor = accentPink,
                        bgColor = accentPink.copy(alpha = 0.16f),
                        modifier = GlanceModifier.defaultWeight().height(26.dp)
                            .clickable(
                                actionRunCallback<AdjustLedgerActionCallback>(
                                    actionParametersOf(
                                        AdjustLedgerActionCallback.AccountKey to "Cash",
                                        AdjustLedgerActionCallback.DeltaKey to -100.0
                                    )
                                )
                            )
                    )

                    Spacer(modifier = GlanceModifier.width(6.dp))

                    // +100 Crd
                    AdjustButtonPill(
                        label = "+100 Crd",
                        textColor = accentGreen,
                        bgColor = accentGreen.copy(alpha = 0.16f),
                        modifier = GlanceModifier.defaultWeight().height(26.dp)
                            .clickable(
                                actionRunCallback<AdjustLedgerActionCallback>(
                                    actionParametersOf(
                                        AdjustLedgerActionCallback.AccountKey to "Card",
                                        AdjustLedgerActionCallback.DeltaKey to 100.0
                                    )
                                )
                            )
                    )
                }
            }
        }
    }

    @Composable
    private fun AdjustButtonPill(
        label: String,
        textColor: Color,
        bgColor: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .cornerRadius(13.dp)
                .background(bgColor),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(textColor),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}

class DailyMoneyGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyMoneyGlanceWidget()
}
