import SwiftUI
import DailyCore

/// Full-screen distraction-free article reader featuring the WinUI Liquid Glass reading template, font controls, and smart recommendations.
public struct NewsReaderView: View {
    public let initialArticle: NewsArticle
    public let candidatePool: [NewsArticle]
    public let onDismiss: () -> Void
    
    @State private var currentArticle: NewsArticle
    @State private var isLoadingFullArticle = true
    @State private var fontSizeMultiplier: Double = 1.0
    @State private var recommendations: [NewsArticle] = []
    @State private var showRecommendations = true
    
    @ObservedObject private var savedService = SavedArticlesService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    @Environment(\.colorScheme) private var systemColorScheme
    
    public init(
        article: NewsArticle,
        candidatePool: [NewsArticle] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.initialArticle = article
        self.candidatePool = candidatePool
        self.onDismiss = onDismiss
        self._currentArticle = State(initialValue: article)
    }
    
    private var isDark: Bool {
        switch settingsService.settings.theme {
        case .system: return systemColorScheme == .dark
        case .dark: return true
        case .light: return false
        }
    }
    
    private var isReadLater: Bool {
        savedService.isReadLater(url: currentArticle.link)
    }
    
    private var isFavorite: Bool {
        savedService.isFavorite(url: currentArticle.link)
    }
    
    public var body: some View {
        ZStack {
            // Background Canvas matching Liquid Glass theme
            Color(hex: isDark ? "#1A1423" : "#EDE5D9")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Glass Toolbar
                readerToolbar
                
                // Article Content Canvas
                ZStack(alignment: .bottom) {
                    if isLoadingFullArticle {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(ThemeColors.accentCyan)
                            Text("Extracting Distraction-Free Article...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ArticleWebView(
                            article: currentArticle,
                            isDark: isDark,
                            fontSizeMultiplier: fontSizeMultiplier
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Floating Bottom Recommendations Bar
                    if !recommendations.isEmpty {
                        bottomRecommendationsBar
                    }
                }
            }
        }
        .task {
            loadArticle(initialArticle)
        }
    }
    
    private var readerToolbar: some View {
        HStack(spacing: 12) {
            // Dismiss Button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            // Publication Branding
            HStack(spacing: 6) {
                if let icon = currentArticle.publicationIconUrl, let url = URL(string: icon) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .scaledToFill()
                                .frame(width: 18, height: 18)
                                .clipShape(Circle())
                        default:
                            EmptyView()
                        }
                    }
                }
                
                Text(currentArticle.publicationName ?? "Reader")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Font Size Toggle (A- / A+)
            Button {
                withAnimation {
                    if fontSizeMultiplier >= 1.3 {
                        fontSizeMultiplier = 0.85
                    } else {
                        fontSizeMultiplier += 0.15
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("A")
                        .font(.system(size: 11, weight: .semibold))
                    Text("A")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 36, height: 32)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            
            // Read Later Bookmark Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    savedService.toggleReadLater(for: currentArticle)
                }
                triggerHaptic()
            } label: {
                Image(systemName: isReadLater ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isReadLater ? ThemeColors.accentCyan : .white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isReadLater ? ThemeColors.accentCyan.opacity(0.2) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            
            // Favorite Star Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    savedService.toggleFavorite(for: currentArticle)
                }
                triggerHaptic()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.2) : .white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.2).opacity(0.2) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            
            // Open in Safari Button
            if let url = URL(string: currentArticle.link) {
                Link(destination: url) {
                    Image(systemName: "safari")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.1))
        }
    }
    
    private var bottomRecommendationsBar: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Related Stories")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        showRecommendations.toggle()
                    }
                } label: {
                    Image(systemName: showRecommendations ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            
            if showRecommendations {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recommendations) { item in
                            Button {
                                loadArticle(item)
                            } label: {
                                HStack(spacing: 8) {
                                    if let icon = item.publicationIconUrl, let url = URL(string: icon) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable()
                                                    .scaledToFill()
                                                    .frame(width: 14, height: 14)
                                                    .clipShape(Circle())
                                            default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                    
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(maxWidth: 220, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
    
    private func loadArticle(_ article: NewsArticle) {
        currentArticle = article
        isLoadingFullArticle = true
        
        // Compute smart recommendations
        let pool = candidatePool.isEmpty ? NewsService.shared.articles : candidatePool
        recommendations = SmartRecommendationEngine.shared.getRecommendations(
            for: article,
            candidatePool: pool,
            limit: 8
        )
        
        Task {
            let full = await NewsService.shared.fetchFullArticle(article: article)
            await MainActor.run {
                self.currentArticle = full
                self.isLoadingFullArticle = false
            }
        }
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
}
