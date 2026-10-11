import SwiftUI
import DailyCore

public struct OrbitSettingsSection: View {
    @ObservedObject private var orbitService = OrbitWatchService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var isWatchesExpanded: Bool = false
    @State private var selectedPlatform: WatchPlatform = .watchOS
    @State private var pinCode: String = ""
    @State private var watchToUnpair: PairedWatch? = nil
    @State private var showUnpairConfirmation: Bool = false
    @FocusState private var isPinFieldFocused: Bool
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                headerView
                
                // Paired Watches Section
                pairedWatchesView
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // Link New Smartwatch Form
                linkWatchFormView
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // Watch Sync Frequency
                syncFrequencyView
                    .id("orbit_bottom")
            }
        }
        .task {
            await orbitService.loadPairedWatches()
        }
        .alert("Unpair Smartwatch", isPresented: $showUnpairConfirmation, presenting: watchToUnpair) { watch in
            Button("Unpair", role: .destructive) {
                Task {
                    _ = await orbitService.unpairWatch(id: watch.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { watch in
            Text("Are you sure you want to unpair \(watch.displayTitle)? It will be disconnected from cloud sync.")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("DayOne Orbit")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("Direct-to-Cloud Wearable Link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Spacer()
            
            if !orbitService.pairedWatches.isEmpty {
                HStack(spacing: 5) {
                    Circle()
                        .fill(ThemeColors.success)
                        .frame(width: 7, height: 7)
                    Text("\(orbitService.pairedWatches.count) Linked")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.success)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(ThemeColors.success.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Paired Watches List
    
    private var pairedWatchesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAIRED WATCHES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
            
            if orbitService.isLoading && orbitService.pairedWatches.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(ThemeColors.accentCyan)
                    Text("Loading paired watches...")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .padding(.vertical, 6)
            } else if orbitService.pairedWatches.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch.slash")
                        .font(.system(size: 20))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Smartwatches Linked")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("Open DayOne Orbit on your watch to see its 6-digit PIN and pair below.")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            } else {
                let displayWatches = isWatchesExpanded ? orbitService.pairedWatches : Array(orbitService.pairedWatches.prefix(3))
                VStack(spacing: 8) {
                    ForEach(displayWatches) { watch in
                        pairedWatchRow(watch)
                    }
                    
                    if orbitService.pairedWatches.count > 3 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isWatchesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isWatchesExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text(isWatchesExpanded ? "Show Less" : "Show All (\(orbitService.pairedWatches.count) Watches)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(ThemeColors.accentCyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(ThemeColors.accentCyan.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
    
    private func pairedWatchRow(_ watch: PairedWatch) -> some View {
        HStack(spacing: 12) {
            // Platform Icon
            ZStack {
                Circle()
                    .fill(Color(hex: watch.platformType?.brandColorHex ?? "#00D2FF").opacity(0.18))
                    .frame(width: 36, height: 36)
                
                Image(systemName: watch.platformType?.systemImage ?? "applewatch")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: watch.platformType?.brandColorHex ?? "#00D2FF"))
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(watch.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(watch.platformType?.displayName ?? watch.platform.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let pairedDate = watch.pairedAt {
                    Text("Paired \(dateFormatter.string(from: pairedDate))")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                } else {
                    Text("Active cloud connection")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
            
            Spacer()
            
            // Unpair Action
            Button {
                watchToUnpair = watch
                showUnpairConfirmation = true
            } label: {
                Text("Unpair")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#FF6B6B"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#FF6B6B").opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color(hex: "#FF6B6B").opacity(0.25), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Link New Smartwatch Form
    
    private var linkWatchFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SMARTWATCH PAIRING")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                Text("Select your watch platform and enter the 6-digit PIN displayed on your watch screen.")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            // Custom Platform Pills (No truncation, with icons)
            HStack(spacing: 6) {
                ForEach(WatchPlatform.allCases) { platform in
                    let isSelected = selectedPlatform == platform
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedPlatform = platform
                            orbitService.pairingError = nil
                            orbitService.pairingSuccessMessage = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: platform.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(platform.shortDisplayName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 6-Digit PIN Input Box Display
            VStack(spacing: 8) {
                ZStack {
                    // Hidden native TextField for input capture
                    TextField("", text: Binding(
                        get: { pinCode },
                        set: { val in
                            let filtered = val.filter { $0.isNumber }
                            pinCode = String(filtered.prefix(6))
                            orbitService.pairingError = nil
                            orbitService.pairingSuccessMessage = nil
                        }
                    ))
                    .keyboardType(.numberPad)
                    .focused($isPinFieldFocused)
                    .opacity(0.01)
                    .frame(height: 52)
                    
                    // Styled 6-cell boxes
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            let char: String = {
                                if index < pinCode.count {
                                    let strIndex = pinCode.index(pinCode.startIndex, offsetBy: index)
                                    return String(pinCode[strIndex])
                                }
                                return ""
                            }()
                            let isCurrent = isPinFieldFocused && index == pinCode.count
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 52)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(
                                                isCurrent ? ThemeColors.accentCyan : (char.isEmpty ? Color.white.opacity(0.14) : Color.white.opacity(0.3)),
                                                lineWidth: isCurrent ? 1.5 : 1
                                            )
                                    )
                                
                                Text(char.isEmpty ? "—" : char)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(char.isEmpty ? ThemeColors.fgMutedDark.opacity(0.5) : .white)
                            }
                            .onTapGesture {
                                isPinFieldFocused = true
                            }
                        }
                    }
                }
                
                // Submit Button
                Button {
                    isPinFieldFocused = false
                    Task {
                        let success = await orbitService.pairWatch(pin: pinCode, platform: selectedPlatform)
                        if success {
                            pinCode = ""
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if orbitService.isPairing {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(orbitService.isPairing ? "Linking Watch..." : "Link \(selectedPlatform.displayName)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        pinCode.count == 6 && !orbitService.isPairing
                            ? Capsule().fill(ThemeColors.accentCyan)
                            : Capsule().fill(ThemeColors.accentCyan.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(pinCode.count != 6 || orbitService.isPairing)
            }
            
            // Feedback Message Banner
            if let errorMsg = orbitService.pairingError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.error)
                    Text(errorMsg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.error)
                    Spacer()
                }
                .padding(10)
                .background(ThemeColors.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let successMsg = orbitService.pairingSuccessMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.success)
                    Text(successMsg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.success)
                    Spacer()
                }
                .padding(10)
                .background(ThemeColors.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - Watch Sync Frequency
    
    private var syncFrequencyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WATCH SYNC FREQUENCY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                Text("Controls how often smartwatches wake up in the background to batch upload health vitals to the cloud. More frequent syncs consume more watch battery.")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Picker("Sync Frequency", selection: Binding(
                get: { settingsService.settings.watchSyncFrequency },
                set: { val in orbitService.setWatchSyncFrequency(val) }
            )) {
                Text("Every 15 min").tag(15)
                Text("Every 30 min").tag(30)
                Text("Hourly").tag(60)
            }
            .pickerStyle(.segmented)
        }
    }
}
