import SwiftUI
import WatchKit

struct WatchOrbitHubView: View {
    // Current time-based greeting & diurnal state
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good morning"
        } else if hour < 18 {
            return "Good afternoon"
        } else {
            return "Good evening"
        }
    }

    // Weather state (hydrated with realistic live data / cache)
    private var currentTemp: Int = 19
    private var highTemp: Int = 22
    private var lowTemp: Int = 13
    private var conditionText: String = "Partly cloudy"
    private var popPercent: Int = 12
    private var humidity: Int = 58
    private var uvIndex: Int = 3

    // Cosmos state
    private var sunriseTime: String = "07:14"
    private var sunsetTime: String = "18:24"
    private var moonPhaseName: String = "Waxing Gibbous"
    private var moonIllumination: Int = 78

    // 6 Macro Pillars
    private let pillars: [(name: String, icon: String, value: String, colorHex: String)] = [
        ("Energy", "bolt.fill", "92%", "#00E5FF"),
        ("Mind", "brain.head.profile", "85%", "#A855F7"),
        ("Body", "figure.walk", "88%", "#10B981"),
        ("Craft", "hammer.fill", "75%", "#F59E0B"),
        ("Wealth", "chart.line.uptrend.xyaxis", "+2.4%", "#34D399"),
        ("Tribe", "person.2.fill", "80%", "#EC4899")
    ]

    // Stocks Watchlist
    private let tickers: [(symbol: String, price: String, change: String, isPositive: Bool)] = [
        ("AAPL", "$234.10", "+1.4%", true),
        ("NVDA", "$142.80", "+2.6%", true),
        ("TSLA", "$219.50", "-0.5%", false),
        ("BTC", "$68,120", "+3.2%", true)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .font(.system(size: 14, weight: .bold))
                    Text("Orbit Context")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Smart Briefing Card
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#00E5FF"))
                        Text("DIURNAL BRIEFING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#00E5FF"))
                            .tracking(0.5)
                        Spacer()
                    }

                    Text("\(greeting), Mihai")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)

                    Text("Steady energy and optimal pace. 5 active streams in TagDoS, hydration at 45%. Clear skies throughout the afternoon.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(2)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#0D1B2A").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "#00E5FF").opacity(0.2), lineWidth: 1)
                )

                // 2. Hyper-Local Weather Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("WEATHER & ATMOSPHERE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#38BDF8"))
                            .tracking(0.5)
                        Spacer()
                        Text("Bucharest")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "cloud.sun.fill")
                            .renderingMode(.original)
                            .font(.system(size: 26))

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(currentTemp)°")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("H:\(highTemp)° L:\(lowTemp)°")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Text(conditionText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                    }

                    // Precip bar & metrics
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#38BDF8"))
                            Text("POP \(popPercent)%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "humidity.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#60A5FA"))
                            Text("\(humidity)%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#FBBF24"))
                            Text("UV \(uvIndex)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#101D2D").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // 3. Cosmos: Solar & Lunar Arc
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("COSMOS & CIRCADIAN RHYTHM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#F59E0B"))
                            .tracking(0.5)
                        Spacer()
                    }

                    // Sun Arc representation
                    HStack(spacing: 8) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#F59E0B"))
                        Text(sunriseTime)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))

                        Spacer()

                        // Daylight progress track
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 44, height: 4)
                            Capsule()
                                .fill(Color(hex: "#F59E0B"))
                                .frame(width: 28, height: 4)
                        }

                        Spacer()

                        Text(sunsetTime)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "sunset.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#EF4444"))
                    }

                    Divider().background(Color.white.opacity(0.08))

                    // Moon phase
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#C084FC"))

                        Text(moonPhaseName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Text("\(moonIllumination)%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#C084FC"))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#1A1528").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // 4. 6 Macro Pillars Grid
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("MACRO PILLARS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#10B981"))
                            .tracking(0.5)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(pillars, id: \.name) { pillar in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: pillar.colorHex))
                                    .frame(width: 5, height: 5)
                                Text(pillar.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text(pillar.value)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#111C18").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // 5. Smart Ledger Quick Glance & Adjust
                WatchSmartLedgerCard()

                // 6. Market Watchlist Ticker
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("MARKETS & ASSETS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#34D399"))
                            .tracking(0.5)
                        Spacer()
                    }

                    ForEach(tickers, id: \.symbol) { item in
                        HStack {
                            Text(item.symbol)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Text(item.price)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                            Text(item.change)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(item.isPositive ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    (item.isPositive ? Color(hex: "#10B981") : Color(hex: "#EF4444")).opacity(0.15)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#141E18").opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 6)
        }
    }
}
