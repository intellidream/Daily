using System;
using System.ComponentModel;
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

        public RssItemViewModel(RssItem item)
        {
            Item = item;
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
            _articleService = App.Current.Services.GetRequiredService<IRssArticleService>();
            RefreshState();
        }

        public string Title => Item.Title;
        public string Link => Item.Link;
        public DateTime PublishDate => Item.PublishDate;
        public string? ImageUrl => Item.ImageUrl;
        public string? Description => Item.Description;
        public string? Author => Item.Author;
        public string? PublicationName => Item.PublicationName;
        public string? PublicationIconUrl => Item.PublicationIconUrl;

        public bool IsMediumItem => PublicationName == "Medium Reading List";

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
}
