import SwiftUI
import DailyCore

/// Liquid Glass modal sheet for searching and switching cities worldwide.
public struct CitySearchSheet: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var searchResults: [LocationSuggestion] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    private let quickCities: [(name: String, country: String, lat: Double, lon: Double)] = [
        ("Bucharest", "Romania", 44.4268, 26.1025),
        ("London", "United Kingdom", 51.5074, -0.1278),
        ("New York", "United States", 40.7128, -74.0060),
        ("Tokyo", "Japan", 35.6762, 139.6503),
        ("Paris", "France", 48.8566, 2.3522),
        ("San Francisco", "United States", 37.7749, -122.4194)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                VStack(spacing: 16) {
                    // Search Input Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Search city or region...", text: $searchQuery)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onChange(of: searchQuery) { _, newValue in
                                performSearch(query: newValue)
                            }

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        if isSearching {
                            ProgressView()
                                .tint(ThemeColors.accentCyan)
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Auto Location Reset Option
                    Button {
                        Task {
                            await weatherService.resetToAutoLocation()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(ThemeColors.accentCyan.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "location.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Location")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Automatic GPS & Network detection")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Spacer()

                            if weatherService.isAutoLocation {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        }
                    }
                    .padding(.horizontal, 16)

                    // Results or Quick Picks
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if !searchResults.isEmpty {
                                Text("SEARCH RESULTS")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .tracking(0.8)
                                    .padding(.horizontal, 20)

                                ForEach(searchResults) { suggestion in
                                    locationRow(title: suggestion.name, subtitle: suggestion.displayName) {
                                        Task {
                                            await weatherService.setManualLocation(
                                                name: suggestion.name,
                                                latitude: suggestion.lat,
                                                longitude: suggestion.lon
                                            )
                                            dismiss()
                                        }
                                    }
                                }
                            } else if searchQuery.isEmpty {
                                Text("POPULAR CITIES")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .tracking(0.8)
                                    .padding(.horizontal, 20)

                                ForEach(quickCities, id: \.name) { city in
                                    locationRow(title: city.name, subtitle: city.country) {
                                        Task {
                                            await weatherService.setManualLocation(
                                                name: city.name,
                                                latitude: city.lat,
                                                longitude: city.lon
                                            )
                                            dismiss()
                                        }
                                    }
                                }
                            } else if !isSearching {
                                VStack(spacing: 8) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.4))
                                    Text("No matching cities found")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }

    private func locationRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(ThemeColors.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            .padding(.horizontal, 16)
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            let results = await weatherService.searchLocations(query: trimmed)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
}
