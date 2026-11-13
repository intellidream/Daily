import SwiftUI
import DailyCore

/// Liquid Glass article card for feed lists featuring high-contrast typography, thumbnails, and quick actions.
public struct NewsArticleCard: View {
    public let article: NewsArticle
    public let onTap: () -> Void
    public let onOpenPerspectives: ((NewsArticle, StoryCluster) -> Void)?
    
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var savedService = SavedArticlesService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var showSourceTransparency = false
    
    public init(
        article: NewsArticle,
        onOpenPerspectives: ((NewsArticle, StoryCluster) -> Void)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.article = article
        self.onOpenPerspectives = onOpenPerspectives
        self.onTap = onTap
    }
    
    private var outletProfile: MediaOutletProfile {
        MediaIntelligenceRegistry.shared.resolve(for: article)
    }
    
    private var articleFraming: ArticleFramingTag {
        ArticleFramingAnalyzer.classify(
            title: article.title,
            description: article.description,
            link: article.link,
            profile: outletProfile
        )
    }
    
    private var storyCluster: StoryCluster? {
        newsService.cluster(for: article)
    }
    
    private var isReadLater: Bool {
        savedService.isReadLater(url: article.link)
    }
    
    private var isFavorite: Bool {
        savedService.isFavorite(url: article.link)
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                    // Header: Publication, Category Pill & Timestamp
                    HStack(alignment: .center, spacing: 8) {
                        // Publication Favicon
                        if let iconUrl = article.publicationIconUrl, let url = URL(string: iconUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 18, height: 18)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "newspaper.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                        }
                        
                        Button {
                            showSourceTransparency = true
                        } label: {
                            Text(article.publicationName ?? outletProfile.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSourceTransparency) {
                            SourceTransparencyPopover(profile: outletProfile) {
                                showSourceTransparency = false
                            }
                        }
                        
                        OutletMicroBadge(profile: outletProfile, framing: articleFraming, compact: true) {
                            showSourceTransparency = true
                        }
                        
                        if let category = article.category {
                            Text(category.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                )
                        }
                        
                        Spacer()
                        
                        Text(article.relativeTimeFormatted)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    // Body: Title, Description & Thumbnail (Clickable Button)
                    Button {
                        onTap()
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(article.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                
                                if let desc = article.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            
                            Spacer(minLength: 0)
                            
                            if let imgStr = article.imageUrl, let url = URL(string: imgStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                            )
                                            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                                    default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Variant A: Multi-Source Bias Spectrum Bar (rendered ONLY when >= 2 outlets cover the story)
                    if let cluster = storyCluster, cluster.hasMultipleSources {
                        BiasSpectrumBar(cluster: cluster, showActionPill: true) {
                            if let onOpenPerspectives = onOpenPerspectives {
                                onOpenPerspectives(article, cluster)
                            } else {
                                onTap()
                            }
                        }
                    }
                    
                    // Actions Footer: Read Later, Favorite, Share
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            if let author = article.author, !author.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10))
                                    Text(author)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                            }
                            
                            if let mediumUser = extractMediumUsername(from: article) {
                                let isSubscribed = newsService.isSubscribedToMediumAuthor(username: mediumUser)
                                Button {
                                    if !isSubscribed {
                                        withAnimation {
                                            newsService.subscribeToMediumAuthor(username: mediumUser, authorName: article.author)
                                        }
                                        triggerHaptic()
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                                            .font(.system(size: 10))
                                        Text(isSubscribed ? "Following" : "Follow")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(isSubscribed ? .white.opacity(0.6) : ThemeColors.accentCyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(isSubscribed ? Color.white.opacity(0.06) : ThemeColors.accentCyan.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if let substackInfo = extractSubstackInfo(from: article) {
                                let isSubscribed = newsService.isSubscribedToSubstack(feedUrl: substackInfo.feedUrl)
                                Button {
                                    if !isSubscribed {
                                        withAnimation {
                                            newsService.subscribeToSubstackPublication(
                                                name: substackInfo.name,
                                                feedUrl: substackInfo.feedUrl,
                                                iconUrl: article.publicationIconUrl ?? ""
                                            )
                                        }
                                        triggerHaptic()
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                                            .font(.system(size: 10))
                                        Text(isSubscribed ? "Subscribed" : "Subscribe")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(isSubscribed ? .white.opacity(0.6) : ThemeColors.accentCyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(isSubscribed ? Color.white.opacity(0.06) : ThemeColors.accentCyan.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Spacer()
                        
                        // Read Later Toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                savedService.toggleReadLater(for: article)
                            }
                            triggerHaptic()
                        } label: {
                            Image(systemName: isReadLater ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isReadLater ? ThemeColors.accentCyan : ThemeColors.fgMutedDark)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(isReadLater ? ThemeColors.accentCyan.opacity(0.15) : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        // Favorite Toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                savedService.toggleFavorite(for: article)
                            }
                            triggerHaptic()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.2) : ThemeColors.fgMutedDark)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.2).opacity(0.15) : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        // Native Share Sheet
                        if let shareUrl = URL(string: article.link) {
                            ShareLink(item: shareUrl, subject: Text(article.title)) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle().fill(Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
    
    private func extractMediumUsername(from article: NewsArticle) -> String? {
        guard article.link.contains("medium.com") else { return nil }
        if let url = URL(string: article.link) {
            if url.path.hasPrefix("/@") {
                let parts = url.path.dropFirst(2).split(separator: "/")
                if let user = parts.first, !user.isEmpty {
                    return String(user)
                }
            }
            if let host = url.host, host.contains(".medium.com") {
                let sub = host.split(separator: ".").first
                if let s = sub, s != "www" && s != "api" {
                    return String(s)
                }
            }
        }
        if let author = article.author, author.hasPrefix("@") {
            return String(author.dropFirst())
        }
        return nil
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
}
