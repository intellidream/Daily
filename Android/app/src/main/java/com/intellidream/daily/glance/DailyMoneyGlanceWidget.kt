package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
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
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.R
import kotlin.math.roundToInt

class DailyMoneyGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyMoneyGlanceWidget()
}

class DailyMoneyGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val parsed = app?.smartLedgerRepository?.parsedLedger?.value

        val allItems = parsed?.sections?.flatMap { it.items } ?: emptyList()
        val cardItem = allItems.firstOrNull { it.displayName.contains("Card", true) || it.key.contains("Card", true) }
        val cashItem = allItems.firstOrNull { it.displayName.contains("Cash", true) || it.key.contains("Cash", true) }

        val cardAmount = cardItem?.calculatedAmount ?: 15100.0
        val cashAmount = cashItem?.calculatedAmount ?: 900.0
        val depositsTotal = parsed?.depositTotal ?: 127156.47
        val netWorthLei = parsed?.netWorth ?: (depositsTotal + cardAmount + cashAmount)
        val netWorthEUR = parsed?.netWorthEUR ?: (netWorthLei / 5.0)

        val incomingTotal = 16000.0
        val outgoingTotal = 16000.0

        val topOutgoing = listOf(
            "Vacante" to 6800.0,
            "Rata" to 4900.0,
            "Cora" to 1000.0
        )

        val formattedEUR = WidgetVisualGraphics.formatCompactEUR(netWorthEUR)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_FINANCES_MONEY"
            data = Uri.parse("daily://finances/money")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_FINANCES)
        }

        provideContent {
            val size = LocalSize.current
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .appWidgetBackground()
                        .background(ImageProvider(R.drawable.widget_background))
                        .cornerRadius(22.dp)
                        .clickable(actionStartActivity(launchIntent))
                ) {
                    when {
                        size.width >= 220.dp && size.height >= 180.dp -> LargeMoneyLayout(
                            netWorthLei = netWorthLei,
                            netWorthEUR = netWorthEUR,
                            depositsTotal = depositsTotal,
                            cardAmount = cardAmount,
                            cashAmount = cashAmount,
                            topOutgoing = topOutgoing
                        )
                        size.width >= 220.dp -> MediumMoneyLayout(
                            netWorthLei = netWorthLei,
                            formattedEUR = formattedEUR,
                            incomingTotal = incomingTotal,
                            outgoingTotal = outgoingTotal,
                            cardAmount = cardAmount,
                            cashAmount = cashAmount
                        )
                        else -> SmallMoneyLayout(
                            netWorthLei = netWorthLei,
                            netWorthEUR = netWorthEUR,
                            cardAmount = cardAmount,
                            cashAmount = cashAmount
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 1. SMALL LAYOUT (systemSmall: 2x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun SmallMoneyLayout(
        netWorthLei: Double,
        netWorthEUR: Double,
        cardAmount: Double,
        cashAmount: Double
    ) {
        val watermarkBitmap = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.WALLET,
            sizePx = 140,
            colorInt = android.graphics.Color.parseColor("#00E676"),
            opacity = 0.14f
        )

        Box(modifier = GlanceModifier.fillMaxSize()) {
            // Trailing Watermark Wallet
            Box(
                modifier = GlanceModifier.fillMaxSize().padding(end = 6.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Image(
                    provider = ImageProvider(watermarkBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.size(59.dp)
                )
            }

            // Foreground Content
            Column(
                modifier = GlanceModifier.fillMaxSize().padding(11.dp)
            ) {
                // Top Section: Net Worth on Left, EUR pill in Top-Right
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top
                ) {
                    Column {
                        Text(
                            text = "${WidgetVisualGraphics.formatCompactNumber(netWorthLei)} Lei",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "NET WORTH",
                            style = TextStyle(
                                color = ColorProvider(Color(0x73FFFFFF)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    // EUR Badge Pill
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x2E00E5FF))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 5.5.dp, vertical = 2.5.dp)
                    ) {
                        Text(
                            text = WidgetVisualGraphics.formatCompactEUR(netWorthEUR),
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Liquid balances: Card and Cash
                Column {
                    Text(
                        text = "Card ${WidgetVisualGraphics.formatCompactNumber(cardAmount)}",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.height(2.dp))
                    Text(
                        text = "Cash ${WidgetVisualGraphics.formatCompactNumber(cashAmount)}",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E676)),
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // 2 Compact Adjust Buttons: -100 Crd & +100 Crd
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    MoneyActionButton(
                        label = "-100 Crd",
                        color = Color(0xFFFF2D55),
                        account = "Card",
                        delta = -100.0,
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    MoneyActionButton(
                        label = "+100 Crd",
                        color = Color(0xFF00E676),
                        account = "Card",
                        delta = 100.0,
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumMoneyLayout(
        netWorthLei: Double,
        formattedEUR: String,
        incomingTotal: Double,
        outgoingTotal: Double,
        cardAmount: Double,
        cashAmount: Double
    ) {
        val walletIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.WALLET,
            sizePx = 36,
            colorInt = android.graphics.Color.parseColor("#00E676")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp)
        ) {
            // Header: Wallet icon on left, EUR badge on right (No text title)
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    provider = ImageProvider(walletIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(15.dp)
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                Text(
                    text = formattedEUR,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF00E5FF)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            // 3 Columns: NET WORTH | FLOW | LIQUID
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Column 1: NET WORTH
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Text(
                        text = "NET WORTH",
                        style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "${WidgetVisualGraphics.formatCompactNumber(netWorthLei)} Lei",
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    )
                }

                // Vertical Divider
                Box(modifier = GlanceModifier.width(1.dp).height(28.dp).background(Color(0x1FFFFFFF))) {}

                // Column 2: FLOW (IN/OUT)
                Column(modifier = GlanceModifier.defaultWeight().padding(start = 8.dp)) {
                    Text(
                        text = "FLOW (IN/OUT)",
                        style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "${WidgetVisualGraphics.formatCompactNumber(incomingTotal)} / ${WidgetVisualGraphics.formatCompactNumber(outgoingTotal)}",
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    )
                }

                // Vertical Divider
                Box(modifier = GlanceModifier.width(1.dp).height(28.dp).background(Color(0x1FFFFFFF))) {}

                // Column 3: LIQUID
                Column(modifier = GlanceModifier.defaultWeight().padding(start = 8.dp)) {
                    Text(
                        text = "LIQUID",
                        style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "Crd ${WidgetVisualGraphics.formatCompactNumber(cardAmount)} · Csh ${WidgetVisualGraphics.formatCompactNumber(cashAmount)}",
                        style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 11.5.sp, fontWeight = FontWeight.Bold)
                    )
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // 3 Smart Interactive Adjust Buttons
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                MoneyActionButton("-100 Crd", Color(0xFFFF2D55), "Card", -100.0, 24.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                MoneyActionButton("-100 Csh", Color(0xFFFF2D55), "Cash", -100.0, 24.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                MoneyActionButton("+100 Crd", Color(0xFF00E676), "Card", 100.0, 24.dp, GlanceModifier.defaultWeight())
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeMoneyLayout(
        netWorthLei: Double,
        netWorthEUR: Double,
        depositsTotal: Double,
        cardAmount: Double,
        cashAmount: Double,
        topOutgoing: List<Pair<String, Double>>
    ) {
        val walletIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.WALLET,
            sizePx = 48,
            colorInt = android.graphics.Color.parseColor("#00E676")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header: Large Wallet Icon + Live EUR Badge
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    provider = ImageProvider(walletIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(20.dp)
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                Text(
                    text = WidgetVisualGraphics.formatCompactEUR(netWorthEUR),
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF00E5FF)),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Upper Panel: Net Worth Hero + Deposits/Liquid
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "NET WORTH",
                        style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "${WidgetVisualGraphics.formatCompactNumber(netWorthLei)} Lei",
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Column(horizontalAlignment = Alignment.End) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "Deposits: ",
                            style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 10.sp, fontWeight = FontWeight.Medium)
                        )
                        Text(
                            text = "${WidgetVisualGraphics.formatCompactNumber(depositsTotal)} Lei",
                            style = TextStyle(color = ColorProvider(Color(0xFFA855F7)), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                    Spacer(modifier = GlanceModifier.height(2.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "Liquid: ",
                            style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 10.sp, fontWeight = FontWeight.Medium)
                        )
                        Text(
                            text = "${WidgetVisualGraphics.formatCompactNumber(cardAmount)} / ${WidgetVisualGraphics.formatCompactNumber(cashAmount)} Lei",
                            style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Divider
            Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(Color(0x1FFFFFFF))) {}

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Key Outgoing Allocations Capsules
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Text(
                    text = "TOP OUTGOING ALLOCATIONS",
                    style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                )

                Spacer(modifier = GlanceModifier.height(6.dp))

                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    for ((name, amount) in topOutgoing) {
                        Box(
                            modifier = GlanceModifier
                                .background(Color(0x14FFFFFF))
                                .cornerRadius(12.dp)
                                .padding(horizontal = 7.dp, vertical = 4.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = name,
                                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 10.sp, fontWeight = FontWeight.Medium)
                                )
                                Spacer(modifier = GlanceModifier.width(4.dp))
                                Text(
                                    text = WidgetVisualGraphics.formatCompactNumber(amount),
                                    style = TextStyle(color = ColorProvider(Color(0xFFFF2D55)), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                )
                            }
                        }
                        Spacer(modifier = GlanceModifier.width(6.dp))
                    }
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // Bottom Actions Panel
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                // Divider
                Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(Color(0x1FFFFFFF))) {}

                Spacer(modifier = GlanceModifier.height(10.dp))

                // Quick Adjust Action Grid (3 buttons, height 32.dp)
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    MoneyActionButton("-100 Card", Color(0xFFFF2D55), "Card", -100.0, 32.dp, GlanceModifier.defaultWeight())
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    MoneyActionButton("-100 Cash", Color(0xFFFF2D55), "Cash", -100.0, 32.dp, GlanceModifier.defaultWeight())
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    MoneyActionButton("+100 Card", Color(0xFF00E676), "Card", 100.0, 32.dp, GlanceModifier.defaultWeight())
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Action Button Component
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MoneyActionButton(
        label: String,
        color: Color,
        account: String,
        delta: Double,
        height: androidx.compose.ui.unit.Dp,
        modifier: GlanceModifier = GlanceModifier
    ) {
        val bgTint = color.copy(alpha = 0.14f)
        Box(
            modifier = modifier
                .height(height)
                .background(bgTint)
                .cornerRadius(height / 2)
                .clickable(
                    actionRunCallback<AdjustLedgerActionCallback>(
                        actionParametersOf(
                            AdjustLedgerActionCallback.AccountKey to account,
                            AdjustLedgerActionCallback.DeltaKey to delta
                        )
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(color),
                    fontSize = if (height >= 30.dp) 11.sp else 10.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}
