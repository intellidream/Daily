import SwiftUI
import DailyCore

/// Horizontal scrolling Liquid Glass carousel displaying AI-powered related articles.
public struct SmartRecommendationsCarousel: View {
    public let recommendations: [NewsArticle]
    public let onSelect: (NewsArticle) -> Void
    
    public init(recommendations: [NewsArticle], onSelect: @escaping (NewsArticle) -> Void) {
        self.recommendations = recommendations
        self.onSelect = onSelect
    }
    
    public var body: some View {
        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Recommended Next", systemImage: "sparkles")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    Spacer()
                    Text("Related Insights")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recommendations) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                GlassCard(cornerRadius: 16, padding: 12) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        // Thumbnail
                                        if let imgStr = item.imageUrl, let url = URL(string: imgStr) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable()
                                                        .scaledToFill()
                                                        .frame(width: 200, height: 110)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                default:
                                                    thumbnailPlaceholder
                                                }
                                            }
                                        } else {
                                            thumbnailPlaceholder
                                        }
                                        
                                        // Publication & Date
                                        HStack(spacing: 6) {
                                            if let pubName = item.publicationName {
                                                Text(pubName)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(ThemeColors.accentCyan)
                                                    .lineLimit(1)
                                            }
                                            Text("•")
                                                .font(.system(size: 9))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                            Text(item.relativeTimeFormatted)
                                                .font(.system(size: 10))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                        }
                                        
                                        // Title
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(width: 200)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [ThemeColors.accentBlue.opacity(0.3), ThemeColors.accentCyan.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 200, height: 110)
            .overlay {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.4))
            }
    }
}
