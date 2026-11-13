using System;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml;
using Daily.Models;
using Daily.Services;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.ViewModels
{
    public sealed class RssItemViewModel : INotifyPropertyChanged
    {
        private readonly IRssArticleService _articleService;

        public RssItem Item { get; }
        public MediaOutletProfile OutletProfile { get; }
        public ArticleFramingTag FramingTag { get; }

        private StoryCluster? _attachedCluster;
        public StoryCluster? AttachedCluster => _attachedCluster;

        public RssItemViewModel(RssItem item, StoryCluster? cluster = null)
        {
            Item = item;
            _attachedCluster = cluster;
            OutletProfile = MediaIntelligenceRegistry.Shared.ResolveArticle(item);
            FramingTag = ArticleFramingAnalyzer.Classify(item.Title, item.Description, item.Link);
            _articleService = App.Current.Services.GetRequiredService<IRssArticleService>();
            RefreshState();
        }

        public RssItemViewModel(LocalSavedArticle savedArticle)
        {
            Item = new RssItem
            {
                Title = savedArticle.Title,
                Link = savedArticle.ArticleUrl,
                PublishDate = savedArticle.ArticleDate,
                ImageUrl = savedArticle.ImageUrl,
                Description = savedArticle.Description,
                Author = savedArticle.Author,
                PublicationName = savedArticle.PublicationName,
                PublicationIconUrl = savedArticle.PublicationIconUrl
            };
            OutletProfile = MediaIntelligenceRegistry.Shared.ResolveArticle(Item);
            FramingTag = ArticleFramingAnalyzer.Classify(Item.Title, Item.Description, Item.Link);
            _articleService = App.Current.Services.GetRequiredService<IRssArticleService>();
            RefreshState();
        }

        public void AttachCluster(StoryCluster? cluster)
        {
            _attachedCluster = cluster;
            OnPropertyChanged(nameof(AttachedCluster));
            OnPropertyChanged(nameof(HasMultipleSources));
            OnPropertyChanged(nameof(LeftStarWidth));
            OnPropertyChanged(nameof(CenterStarWidth));
            OnPropertyChanged(nameof(RightStarWidth));
            OnPropertyChanged(nameof(BiasSummaryLabel));
            OnPropertyChanged(nameof(PerspectivesPillLabel));
            OnPropertyChanged(nameof(HasBlindspot));
            OnPropertyChanged(nameof(BlindspotBadgeText));
        }

        public string Title => Item.Title;
        public string Link => Item.Link;
        public DateTime PublishDate => Item.PublishDate;
        public string? ImageUrl => Item.ImageUrl;
        public string? Description => Item.Description;
        public string? Author => Item.Author;
        public string? PublicationName => Item.PublicationName;
        public string? PublicationIconUrl => Item.PublicationIconUrl;

        // ── Variant A: Ultra-Discreet Outlet Micro-Pill & Framing Badge ──
        public string OutletBadgeText => OutletProfile.CompactCardBadge;
        public bool HasOutletBadge => !string.IsNullOrEmpty(OutletBadgeText);
        public Brush OutletBadgeBackground => BiasPalette.GetBadgeBackground(OutletProfile.Bias);
        public Brush OutletBadgeForeground => BiasPalette.GetBadgeForeground(OutletProfile.Bias);

        public bool HasFramingBadge => FramingTag != ArticleFramingTag.StraightReporting;
        public string FramingBadgeText => FramingTag.DisplayLabel();
        public Brush FramingBadgeForeground => BiasPalette.GetFramingForeground(FramingTag);

        // ── Variant A: Conditional Multi-Source Bias Spectrum Bar (>= 2 outlets) ──
        public bool HasMultipleSources => _attachedCluster is { HasMultipleSources: true };

        public GridLength LeftStarWidth => BiasPalette.GetStarWidth(_attachedCluster?.Distribution, "left");
        public GridLength CenterStarWidth => BiasPalette.GetStarWidth(_attachedCluster?.Distribution, "center");
        public GridLength RightStarWidth => BiasPalette.GetStarWidth(_attachedCluster?.Distribution, "right");

        public string BiasSummaryLabel => _attachedCluster?.Distribution.SummaryLabel ?? string.Empty;
        public string PerspectivesPillLabel => _attachedCluster != null
            ? $"{_attachedCluster.UniqueOutletCount} sources · Perspectives →"
            : string.Empty;

        public bool HasBlindspot => _attachedCluster?.IsBlindspot == true;
        public string BlindspotBadgeText => _attachedCluster?.Blindspot?.BadgeTitle() ?? string.Empty;

        public bool IsMediumItem =>
            PublicationName == "Medium Reading List" ||
            (Link != null && Link.Contains("medium.com"));

        public bool IsSubstackItem =>
            PublicationName == "Substack Inbox" ||
            (Link != null && (Link.Contains("substack.com", StringComparison.OrdinalIgnoreCase) || Link.Contains(".substack.com", StringComparison.OrdinalIgnoreCase))) ||
            (ImageUrl != null && (ImageUrl.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) || ImageUrl.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase))) ||
            (PublicationIconUrl != null && (PublicationIconUrl.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) || PublicationIconUrl.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase) || PublicationIconUrl.Contains("substack.com", StringComparison.OrdinalIgnoreCase))) ||
            (Item.Content != null && (Item.Content.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) || Item.Content.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase) || Item.Content.Contains("captioned-image-container", StringComparison.OrdinalIgnoreCase)));

        public bool CanSubscribe
        {
            get
            {
                if (IsMediumItem) return true;
                if (IsSubstackItem)
                {
                    var (_, feedUrl) = Daily_WinUI.Views.RssFeedDetailPage.ExtractSubstackInfo(Link, true);
                    return !string.IsNullOrEmpty(feedUrl);
                }
                return false;
            }
        }

        private bool _isFavorite;
        public bool IsFavorite
        {
            get => _isFavorite;
            set
            {
                if (_isFavorite != value)
                {
                    _isFavorite = value;
                    OnPropertyChanged();
                    OnPropertyChanged(nameof(FavoriteGlyph));
                    OnPropertyChanged(nameof(FavoriteBrush));
                }
            }
        }

        private bool _isReadLater;
        public bool IsReadLater
        {
            get => _isReadLater;
            set
            {
                if (_isReadLater != value)
                {
                    _isReadLater = value;
                    OnPropertyChanged();
                    OnPropertyChanged(nameof(ReadLaterGlyph));
                    OnPropertyChanged(nameof(ReadLaterBrush));
                }
            }
        }

        public string FavoriteGlyph => IsFavorite ? "\uE735" : "\uE734"; // Star Filled : Empty
        public string ReadLaterGlyph => IsReadLater ? "\uE8A5" : "\uE8A4"; // Bookmark Filled : Empty

        private static Brush GetMutedBrush()
        {
            if (Application.Current.Resources.TryGetValue("AppFgMutedColorBrush", out var brushObj) && brushObj is Brush brush)
            {
                return brush;
            }
            return new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0x80, 0x80, 0x80));
        }

        private static readonly Brush FavoriteActiveBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xF2, 0x99, 0x4A));
        private static readonly Brush ReadLaterActiveBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xFF, 0x52, 0x52));

        public Brush FavoriteBrush => IsFavorite ? FavoriteActiveBrush : GetMutedBrush();
        public Brush ReadLaterBrush => IsReadLater ? ReadLaterActiveBrush : GetMutedBrush();

        public void RefreshState()
        {
            IsFavorite = _articleService.IsSaved(Link, SavedArticleType.Favorite);
            IsReadLater = _articleService.IsSaved(Link, SavedArticleType.ReadLater);
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public sealed class StoryClusterCardViewModel
    {
        public StoryCluster Cluster { get; }

        public StoryClusterCardViewModel(StoryCluster cluster)
        {
            Cluster = cluster;
        }

        public string CanonicalTitle => Cluster.CanonicalTitle;
        public string? HeroImageUrl => Cluster.HeroImageUrl;
        public bool HasHeroImage => !string.IsNullOrWhiteSpace(Cluster.HeroImageUrl);
        public string LatestPublishedText => Cluster.LatestPublishedAt.ToString("MMM d, HH:mm");
        public string UniqueOutletCountLabel => $"{Cluster.UniqueOutletCount} outlets";
        public string BiasSummaryLabel => Cluster.Distribution.SummaryLabel;

        public GridLength LeftStarWidth => BiasPalette.GetStarWidth(Cluster.Distribution, "left");
        public GridLength CenterStarWidth => BiasPalette.GetStarWidth(Cluster.Distribution, "center");
        public GridLength RightStarWidth => BiasPalette.GetStarWidth(Cluster.Distribution, "right");

        public bool HasBlindspot => Cluster.IsBlindspot;
        public string BlindspotBadgeText => Cluster.Blindspot?.BadgeTitle() ?? string.Empty;
        public string BlindspotExplanation => Cluster.Blindspot?.Explanation() ?? string.Empty;

        public string TopOutletsSummary =>
            string.Join("  ·  ", Cluster.Coverage
                .Select(c => $"{c.Outlet.DisplayName} ({c.Outlet.Bias.ShortBadge()})")
                .Distinct()
                .Take(5));
    }

    public sealed class ReaderCoverageRowViewModel
    {
        public ClusterCoverageItem CoverageItem { get; }

        public ReaderCoverageRowViewModel(ClusterCoverageItem item)
        {
            CoverageItem = item;
        }

        public RssItem Article => CoverageItem.Article;
        public string OutletName => CoverageItem.Outlet.DisplayName;
        public string Headline => CoverageItem.Article.Title;
        public string BiasBadgeText => $"{CoverageItem.Outlet.Bias.DisplayLabel()} · {CoverageItem.Outlet.Factuality.ShortLabel()}";
        public Brush BiasBadgeBackground => BiasPalette.GetBadgeBackground(CoverageItem.Outlet.Bias);
        public Brush BiasBadgeForeground => BiasPalette.GetBadgeForeground(CoverageItem.Outlet.Bias);
        public bool HasFramingBadge => CoverageItem.Framing != ArticleFramingTag.StraightReporting;
        public string FramingText => CoverageItem.Framing.DisplayLabel();
        public string OwnerSummary => CoverageItem.Outlet.OwnerName;
    }

    internal static class BiasPalette
    {
        private static readonly Brush LeftBg = new SolidColorBrush(Windows.UI.Color.FromArgb(46, 0x3B, 0x82, 0xF6));
        private static readonly Brush LeftFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0x60, 0xA5, 0xFA));

        private static readonly Brush CenterBg = new SolidColorBrush(Windows.UI.Color.FromArgb(42, 0x94, 0xA3, 0xB8));
        private static readonly Brush CenterFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xCB, 0xD5, 0xE1));

        private static readonly Brush RightBg = new SolidColorBrush(Windows.UI.Color.FromArgb(46, 0xF4, 0x3F, 0x5E));
        private static readonly Brush RightFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xFB, 0x71, 0x85));

        private static readonly Brush IndepBg = new SolidColorBrush(Windows.UI.Color.FromArgb(44, 0x14, 0xB8, 0xA6));
        private static readonly Brush IndepFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0x2D, 0xD4, 0xBF));

        private static readonly Brush AmberFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xFB, 0xBF, 0x24));
        private static readonly Brush CyanFg = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0x38, 0xBD, 0xF8));

        public static Brush GetBadgeBackground(MediaBias bias) => bias switch
        {
            MediaBias.Left or MediaBias.LeanLeft => LeftBg,
            MediaBias.Center => CenterBg,
            MediaBias.LeanRight or MediaBias.Right => RightBg,
            MediaBias.Independent => IndepBg,
            _ => CenterBg
        };

        public static Brush GetBadgeForeground(MediaBias bias) => bias switch
        {
            MediaBias.Left or MediaBias.LeanLeft => LeftFg,
            MediaBias.Center => CenterFg,
            MediaBias.LeanRight or MediaBias.Right => RightFg,
            MediaBias.Independent => IndepFg,
            _ => CenterFg
        };

        public static Brush GetFramingForeground(ArticleFramingTag tag) => tag switch
        {
            ArticleFramingTag.Opinion or ArticleFramingTag.Sensational => AmberFg,
            _ => CyanFg
        };

        public static GridLength GetStarWidth(BiasDistribution? dist, string segment)
        {
            if (dist == null || dist.RatedSpectrumTotal == 0)
            {
                return segment == "center"
                    ? new GridLength(1.0, GridUnitType.Star)
                    : new GridLength(0.0, GridUnitType.Pixel);
            }

            int pct = segment switch
            {
                "left" => dist.LeftPercent,
                "center" => dist.CenterPercent,
                "right" => dist.RightPercent,
                _ => 0
            };

            return pct <= 0
                ? new GridLength(0.0, GridUnitType.Pixel)
                : new GridLength(pct, GridUnitType.Star);
        }
    }
}
