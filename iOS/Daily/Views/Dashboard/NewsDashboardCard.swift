import SwiftUI
import DailyCore

/// Modular News & Briefings Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct NewsDashboardCard: View {
    @ObservedObject private var newsService = NewsService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 20, padding: size == .small ? 14 : 18) {
                switch size {
                case .small:
                    smallContent
                case .wide:
                    wideContent
                case .tall:
                    tallContent
                case .large:
                    largeContent
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Headline Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                
                Spacer()
                
                if let top = newsService.topHeadline, let pub = top.publicationName {
                    Text(pub)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentBlue)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 2)

            if let top = newsService.topHeadline {
                Text(top.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                Spacer(minLength: 2)
                
                Text(top.relativeTimeFormatted)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            } else {
                Text("Loading headlines...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard Lead Headline Card
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("News & Briefings", systemImage: "newspaper.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                HStack(spacing: 4) {
                    Text("Explore Feeds")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }
            
            if let top = newsService.topHeadline {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(top.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 6) {
                            Text(top.publicationName ?? "Briefing")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ThemeColors.accentBlue)
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(top.relativeTimeFormatted)
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    Spacer()
                    
                    if let imgStr = top.imageUrl, let url = URL(string: imgStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Intelligence and Top Stories")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text("World Feeds")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.accentBlue)
                        Text("•")
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("Tap to explore")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
        }
    }

    // MARK: - Tall (1x2) Vertical Double Story Tower
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("News", systemImage: "newspaper.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Text("Briefing")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ThemeColors.accentBlue)
            }

            if let top = newsService.topHeadline {
                // Top Story with Image
                if let imgStr = top.imageUrl, let url = URL(string: imgStr) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .scaledToFill()
                                .frame(height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Text(top.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(top.publicationName ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.accentBlue)
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(top.relativeTimeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                // Secondary Story
                let secondary = newsService.articles.dropFirst().first
                if let second = secondary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(second.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(second.relativeTimeFormatted)
                            .font(.system(size: 9))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }

                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No headlines loaded")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Extended News Digest Hub
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("News & Intelligence", systemImage: "newspaper.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                HStack(spacing: 4) {
                    Text("All Feeds")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            if let top = newsService.topHeadline {
                // Lead Story
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(top.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 6) {
                            Text(top.publicationName ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ThemeColors.accentBlue)
                            Text("•")
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(top.relativeTimeFormatted)
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    Spacer()
                    
                    if let imgStr = top.imageUrl, let url = URL(string: imgStr) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                // Next 2-3 Stories
                let moreStories = Array(newsService.articles.dropFirst().prefix(2))
                VStack(spacing: 10) {
                    ForEach(moreStories) { story in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(story.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                HStack(spacing: 4) {
                                    Text(story.publicationName ?? "")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(ThemeColors.accentBlue)
                                    Text("•")
                                        .font(.system(size: 8))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    Text(story.relativeTimeFormatted)
                                        .font(.system(size: 10))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            
                            Spacer()
                            
                            if let imgStr = story.imageUrl, let url = URL(string: imgStr) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("Tap to explore news & briefings")
                    .font(.system(size: 13))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
