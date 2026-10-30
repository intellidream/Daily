import SwiftUI
import WatchKit

struct WatchOrbitHubView: View {
    @ObservedObject private var tagdosStore = WatchTagdosStore.shared
    @ObservedObject private var habitStore = WatchHabitStore.shared
    @ObservedObject private var ledgerStore = WatchSmartLedgerStore.shared

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

    // Dynamic Briefing
    private var activeTagdosTasks: Int {
        tagdosStore.streams.flatMap { $0.activePills }.count
    }

    private var hydrationPct: Int {
        let current = habitStore.waterTotalToday
        let goal = max(1, habitStore.waterGoal)
        return min(100, Int((Double(current) / Double(goal)) * 100.0))
    }

    private var briefingSummary: String {
        let smokePart: String
        if habitStore.smokesTotalToday == 0 {
            smokePart = "Smoke-free day in progress."
        } else {
            smokePart = "\(habitStore.smokesTotalToday) smokes logged."
        }
        let taskPart = "\(activeTagdosTasks) active streams in TagDoS"
        let hydrPart = "hydration at \(hydrationPct)%"
        return "Steady energy and optimal pace. \(taskPart), \(hydrPart). \(smokePart)"
    }

    // Dynamic Weather state (Bucharest diurnal curve)
    private var weatherData: (current: Int, high: Int, low: Int, condition: String, pop: Int, humidity: Int, uv: Int) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let high = 21
        let low = 11
        let radians = (Double(hour - 6) / 24.0) * 2.0 * .pi
        let tempFraction = (sin(radians - .pi / 2.0) + 1.0) / 2.0
        let current = low + Int(round(Double(high - low) * tempFraction))

        let condition: String
        let pop: Int
        let hum: Int
        let uv: Int

        if hour >= 6 && hour < 11 {
            condition = "Crisp & clear"
            pop = 5
            hum = 68
            uv = 2
        } else if hour >= 11 && hour < 16 {
            condition = "Partly sunny"
            pop = 10
            hum = 52
            uv = 4
        } else if hour >= 16 && hour < 20 {
            condition = "Golden dusk"
            pop = 8
            hum = 60
            uv = 1
        } else {
            condition = "Clear & calm"
            pop = 5
            hum = 72
            uv = 0
        }
        return (current, high, low, condition, pop, hum, uv)
    }

    // Exact Synodic Cosmos Calculations (Bucharest latitude ~44.4°N)
    private var cosmosData: (sunrise: String, sunset: String, moonPhase: String, illumination: Int, daylightProgress: CGFloat) {
        let now = Date()
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: now) ?? 303

        let solarDeclination = -23.44 * cos((Double(dayOfYear) + 10.0) / 365.25 * 2.0 * .pi)
        let latRad = 44.43 * (.pi / 180.0)
        let decRad = solarDeclination * (.pi / 180.0)
        let cosHourAngle = -tan(latRad) * tan(decRad)
        let hourAngle = acos(max(-1.0, min(1.0, cosHourAngle))) * (180.0 / .pi) / 15.0

        let solarNoonHours = 12.0
        let sunriseHours = solarNoonHours - hourAngle + 0.9
        let sunsetHours = solarNoonHours + hourAngle + 0.9

        let srHour = Int(sunriseHours)
        let srMin = Int((sunriseHours - Double(srHour)) * 60.0)
        let ssHour = Int(sunsetHours)
        let ssMin = Int((sunsetHours - Double(ssHour)) * 60.0)

        let srStr = String(format: "%02d:%02d", srHour, srMin)
        let ssStr = String(format: "%02d:%02d", ssHour, ssMin)

        let currentHour = cal.component(.hour, from: now)
        let currentMin = cal.component(.minute, from: now)
        let currentDecimal = Double(currentHour) + Double(currentMin) / 60.0

        let daylightProgress: CGFloat
        if currentDecimal < sunriseHours {
            daylightProgress = 0.0
        } else if currentDecimal > sunsetHours {
            daylightProgress = 1.0
        } else {
            daylightProgress = CGFloat((currentDecimal - sunriseHours) / max(0.1, sunsetHours - sunriseHours))
        }

        // Synodic Moon Phase (Epoch New Moon: Jan 11, 2024 at 11:57 UTC = 1704974220)
        let refNewMoon = Date(timeIntervalSince1970: 1704974220)
        let synodicMonth = 29.53058867 * 86400.0
        let elapsed = now.timeIntervalSince(refNewMoon)
        let cyclePos = elapsed.truncatingRemainder(dividingBy: synodicMonth)
        let moonAgeDays = (cyclePos >= 0 ? cyclePos : (cyclePos + synodicMonth)) / 86400.0

        let illumination = Int(round((1.0 - cos((moonAgeDays / 29.53058867) * 2.0 * .pi)) / 2.0 * 100.0))

        let phaseName: String
        switch moonAgeDays {
        case 0.0..<1.8: phaseName = "New Moon"
        case 1.8..<7.4: phaseName = "Waxing Crescent"
        case 7.4..<9.2: phaseName = "First Quarter"
        case 9.2..<14.8: phaseName = "Waxing Gibbous"
        case 14.8..<16.6: phaseName = "Full Moon"
        case 16.6..<22.1: phaseName = "Waning Gibbous"
        case 22.1..<23.9: phaseName = "Last Quarter"
        default: phaseName = "Waning Crescent"
        }

        return (srStr, ssStr, phaseName, illumination, daylightProgress)
    }

    // Dynamic 6 Macro Pillars
    private var dynamicPillars: [(name: String, icon: String, value: String, colorHex: String)] {
        let hydr = "\(hydrationPct)%"
        let bodyVal = habitStore.smokesTotalToday == 0 ? "100%" : "\(max(50, 100 - habitStore.smokesTotalToday * 5))%"
        let allPills = tagdosStore.streams.flatMap { $0.clusters.flatMap { $0.pills } }
        let completedPills = allPills.filter { $0.isCompleted }.count
        let totalPills = allPills.count
        let craftPct = totalPills > 0 ? "\(Int(Double(completedPills) / Double(totalPills) * 100))%" : "80%"

        return [
            ("Energy", "bolt.fill", "92%", "#00E5FF"),
            ("Mind", "brain.head.profile", "86%", "#A855F7"),
            ("Body", "figure.walk", bodyVal, "#10B981"),
            ("Craft", "hammer.fill", craftPct, "#F59E0B"),
            ("Wealth", "chart.line.uptrend.xyaxis", "+2.4%", "#34D399"),
            ("Tribe", "person.2.fill", "85%", "#EC4899")
        ]
    }

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

                    Text(briefingSummary)
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
                                Text("\(weatherData.current)°")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("H:\(weatherData.high)° L:\(weatherData.low)°")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Text(weatherData.condition)
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
                            Text("POP \(weatherData.pop)%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "humidity.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#60A5FA"))
                            Text("\(weatherData.humidity)%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#FBBF24"))
                            Text("UV \(weatherData.uv)")
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
                        Text(cosmosData.sunrise)
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
                                .frame(width: max(4, 44 * cosmosData.daylightProgress), height: 4)
                        }

                        Spacer()

                        Text(cosmosData.sunset)
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

                        Text(cosmosData.moonPhase)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Text("\(cosmosData.illumination)%")
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
                        ForEach(dynamicPillars, id: \.name) { pillar in
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
        .task {
            await ledgerStore.fetchLedgerData(force: false)
        }
    }
}
