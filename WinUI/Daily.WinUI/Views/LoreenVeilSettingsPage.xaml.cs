using System;
using System.Collections.Generic;
using System.Linq;
using Daily_WinUI.Controls;
using Daily_WinUI.Helpers;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed partial class LoreenVeilSettingsPage : Page
{
    private const double CanvasSize = 240.0;
    private readonly List<List<LoreenPoint>> _userStrokes = new();
    private List<LoreenPoint>? _activeStroke;
    private Polyline? _activePolyline;
    private bool _loading = true;
    private bool _previewForcedReveal;
    private string _challengeWord = "LOREEN";
    private int _currentLetterIndex;
    private readonly HashSet<int> _completedIndices = new();
    private bool _isCustomPracticeOnly;

    public LoreenVeilSettingsPage()
    {
        InitializeComponent();
        Loaded += LoreenVeilSettingsPage_Loaded;
    }

    private void LoreenVeilSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        var settings = SettingsService.Load();
        var auth = App.Current.Services.GetService<WinUIAuthService>();
        string? firstName = auth?.CurrentUserFirstName;
        string normalizedName = LoreenGlyphCatalog.ChallengeWord(firstName);
        if (!string.Equals(normalizedName, "LOREEN", StringComparison.OrdinalIgnoreCase))
        {
            WordNameBtn.Content = normalizedName;
            WordNameBtn.Tag = normalizedName;
            WordNameBtn.Visibility = Visibility.Visible;
        }
        else
        {
            WordNameBtn.Visibility = Visibility.Collapsed;
        }

        ApplySettingsToUI(settings);
        BuildCodexGrid();
        SetupChallengeWord("LOREEN");
        _loading = false;
    }

    private void ApplySettingsToUI(AppSettings settings)
    {
        bool unlocked = settings.LoreenVeilUnlocked;
        UnlockedControlsPanel.Visibility = unlocked ? Visibility.Visible : Visibility.Collapsed;
        InitiationSectionCard.Visibility = unlocked ? Visibility.Collapsed : Visibility.Visible;
        ClosePracticeBtn.Visibility = unlocked ? Visibility.Visible : Visibility.Collapsed;

        MasterVeilSwitch.IsOn = settings.LoreenVeilEnabled;
        ApplyTagdosSwitch.IsOn = settings.LoreenVeilApplyToTagdos;
        ApplyNotesSwitch.IsOn = settings.LoreenVeilApplyToNotes;
        ApplyWidgetsSwitch.IsOn = settings.LoreenVeilApplyToWidgets;
        RequireBiometricSwitch.IsOn = settings.LoreenVeilRequireBiometricsForPeek;

        if (!unlocked)
        {
            StatusBadgeBorder.Background = new SolidColorBrush(Color.FromArgb(0x22, 0xAF, 0x52, 0xDE));
            StatusBadgeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(0x66, 0xAF, 0x52, 0xDE));
            StatusBadgeIcon.Glyph = "\xE72E";
            StatusBadgeIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF));
            StatusBadgeText.Text = "Initiation Required";
            StatusBadgeText.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF));
        }
        else if (settings.LoreenVeilEnabled)
        {
            StatusBadgeBorder.Background = new SolidColorBrush(Color.FromArgb(0x26, 0x00, 0xE6, 0x76));
            StatusBadgeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(0x77, 0x00, 0xE6, 0x76));
            StatusBadgeIcon.Glyph = "\xEA18";
            StatusBadgeIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE6, 0x76));
            StatusBadgeText.Text = "Veil Active";
            StatusBadgeText.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE6, 0x76));
        }
        else
        {
            StatusBadgeBorder.Background = new SolidColorBrush(Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF));
            StatusBadgeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));
            StatusBadgeIcon.Glyph = "\xE785";
            StatusBadgeIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF));
            StatusBadgeText.Text = "Unlocked (Paused)";
            StatusBadgeText.Foreground = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF));
        }

        UpdateLivePreview(settings);
    }

    private void UpdateLivePreview(AppSettings settings)
    {
        bool showVeil = !_previewForcedReveal && (settings.LoreenVeilEnabled || !settings.LoreenVeilUnlocked);
        PreviewLine1.IsVeiled = showVeil;
        PreviewLine2.IsVeiled = showVeil;
        LivePreviewBtnLabel.Text = showVeil ? "Peek in Latin" : "Veil in Loreen";
    }

    private void SetupChallengeWord(string word)
    {
        _challengeWord = LoreenGlyphCatalog.ChallengeWord(word);
        _currentLetterIndex = 0;
        _completedIndices.Clear();
        _isCustomPracticeOnly = false;
        ClearUserStrokes();
        RenderChallengeHeader();
        RenderGhostGuide();
    }

    private void RenderChallengeHeader()
    {
        ChallengeLettersPanel.Children.Clear();
        for (int i = 0; i < _challengeWord.Length; i++)
        {
            bool isDone = _completedIndices.Contains(i);
            bool isCurrent = i == _currentLetterIndex;
            char ch = _challengeWord[i];

            var pill = new Border
            {
                Background = isDone
                    ? new SolidColorBrush(Color.FromArgb(0x33, 0x00, 0xE6, 0x76))
                    : isCurrent
                        ? new SolidColorBrush(Color.FromArgb(0x33, 0x00, 0xE5, 0xFF))
                        : new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
                BorderBrush = isDone
                    ? new SolidColorBrush(Color.FromArgb(0x88, 0x00, 0xE6, 0x76))
                    : isCurrent
                        ? new SolidColorBrush(Color.FromArgb(0x99, 0x00, 0xE5, 0xFF))
                        : new SolidColorBrush(Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Width = 34,
                Height = 34,
                Tag = i
            };
            pill.Child = new TextBlock
            {
                Text = ch.ToString(),
                FontSize = 14,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Foreground = new SolidColorBrush(isDone
                    ? Color.FromArgb(0xFF, 0x00, 0xE6, 0x76)
                    : isCurrent
                        ? Colors.White
                        : Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            pill.Tapped += (_, __) =>
            {
                if (pill.Tag is int idx && idx < _challengeWord.Length)
                {
                    _currentLetterIndex = idx;
                    _isCustomPracticeOnly = false;
                    ClearUserStrokes();
                    RenderChallengeHeader();
                    RenderGhostGuide();
                }
            };
            ChallengeLettersPanel.Children.Add(pill);
        }

        char target = CurrentTargetChar;
        var def = LoreenGlyphCatalog.Definition(target);
        CurrentTargetTitle.Text = _isCustomPracticeOnly
            ? $"Practice glyph: {target}"
            : $"Draw Loreen glyph for: {target} ({_currentLetterIndex + 1}/{_challengeWord.Length})";
        CurrentTargetHint.Text = def != null ? $"{def.Family} — {def.Summary}" : string.Empty;
    }

    private char CurrentTargetChar =>
        _challengeWord.Length > 0 && _currentLetterIndex < _challengeWord.Length
            ? _challengeWord[_currentLetterIndex]
            : 'L';

    private void RenderGhostGuide()
    {
        GhostGuideLayer.Children.Clear();
        if (GhostGuideCheck.IsChecked != true) return;
        var def = LoreenGlyphCatalog.Definition(CurrentTargetChar);
        if (def == null) return;

        var guideBrush = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF));
        foreach (var stroke in def.Strokes)
        {
            if (stroke.Count < 2) continue;
            var poly = new Polyline
            {
                Stroke = guideBrush,
                StrokeThickness = 6,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round
            };
            foreach (var pt in stroke)
            {
                poly.Points.Add(new Point(pt.X * CanvasSize, pt.Y * CanvasSize));
            }
            GhostGuideLayer.Children.Add(poly);
        }
    }

    private void ClearUserStrokes()
    {
        _userStrokes.Clear();
        _activeStroke = null;
        _activePolyline = null;
        UserStrokesLayer.Children.Clear();
    }

    private void StrokeCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var ptr = e.GetCurrentPoint(StrokeCanvas);
        var pos = ptr.Position;
        StrokeCanvas.CapturePointer(e.Pointer);

        _activeStroke = new List<LoreenPoint> { ToNormalized(pos) };
        _userStrokes.Add(_activeStroke);

        _activePolyline = new Polyline
        {
            Stroke = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF)),
            StrokeThickness = 6.5,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round
        };
        _activePolyline.Points.Add(pos);
        UserStrokesLayer.Children.Add(_activePolyline);
    }

    private void StrokeCanvas_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_activeStroke == null || _activePolyline == null) return;
        var pos = e.GetCurrentPoint(StrokeCanvas).Position;
        var pt = ToNormalized(pos);
        var last = _activeStroke[^1];
        if (Math.Abs(pt.X - last.X) + Math.Abs(pt.Y - last.Y) < 0.004) return;
        _activeStroke.Add(pt);
        _activePolyline.Points.Add(pos);
    }

    private void StrokeCanvas_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_activeStroke != null)
        {
            StrokeCanvas.ReleasePointerCapture(e.Pointer);
        }
        _activeStroke = null;
        _activePolyline = null;
    }

    private void StrokeCanvas_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        _activeStroke = null;
        _activePolyline = null;
    }

    private static LoreenPoint ToNormalized(Point p)
    {
        double x = Math.Clamp(p.X / CanvasSize, 0.0, 1.0);
        double y = Math.Clamp(p.Y / CanvasSize, 0.0, 1.0);
        return new LoreenPoint(x, y);
    }

    private void CheckLetter_Click(object sender, RoutedEventArgs e)
    {
        if (_userStrokes.Sum(s => s.Count) < 3)
        {
            RecognitionFeedbackText.Text = "Draw the glyph inside the box first.";
            return;
        }

        char target = CurrentTargetChar;
        var res = LoreenStrokeRecognizer.Recognize(_userStrokes);
        bool ok = LoreenStrokeRecognizer.Matches(_userStrokes, target);

        if (ok)
        {
            if (_isCustomPracticeOnly)
            {
                RecognitionFeedbackText.Text = $"✓ Exact match for Loreen '{target}'!";
                ClearUserStrokes();
                return;
            }

            _completedIndices.Add(_currentLetterIndex);
            ClearUserStrokes();

            if (_completedIndices.Count >= _challengeWord.Length)
            {
                var settings = SettingsService.Load();
                settings.LoreenVeilUnlocked = true;
                settings.LoreenVeilEnabled = true;
                SettingsService.Save(settings);

                _loading = true;
                ApplySettingsToUI(settings);
                _loading = false;
                RecognitionFeedbackText.Text = "✦ Initiation Complete! Loreen Veil is now unlocked and active.";
                return;
            }

            int nextIdx = Enumerable.Range(0, _challengeWord.Length).FirstOrDefault(i => !_completedIndices.Contains(i));
            _currentLetterIndex = nextIdx;
            RecognitionFeedbackText.Text = $"✓ Matched '{target}'! Next letter: {CurrentTargetChar}.";
            RenderChallengeHeader();
            RenderGhostGuide();
        }
        else
        {
            string heard = res != null ? $" (closest match: '{res.Letter}', d={res.Distance:F2})" : string.Empty;
            RecognitionFeedbackText.Text = $"Not quite '{target}'{heard}. Try following the cyan guide.";
            ClearUserStrokes();
        }
    }

    private void ClearStroke_Click(object sender, RoutedEventArgs e)
    {
        ClearUserStrokes();
        RecognitionFeedbackText.Text = $"Cleared canvas for '{CurrentTargetChar}'.";
    }

    private void GhostGuideCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (GhostGuideLayer != null) RenderGhostGuide();
    }

    private void WordPreset_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string word)
        {
            SetupChallengeWord(word);
        }
    }

    private void SettingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var settings = SettingsService.Load();
        settings.LoreenVeilEnabled = MasterVeilSwitch.IsOn;
        settings.LoreenVeilApplyToTagdos = ApplyTagdosSwitch.IsOn;
        settings.LoreenVeilApplyToNotes = ApplyNotesSwitch.IsOn;
        settings.LoreenVeilApplyToWidgets = ApplyWidgetsSwitch.IsOn;
        settings.LoreenVeilRequireBiometricsForPeek = RequireBiometricSwitch.IsOn;
        SettingsService.Save(settings);
        ApplySettingsToUI(settings);
    }

    private void LivePreviewToggle_Click(object sender, RoutedEventArgs e)
    {
        _previewForcedReveal = !_previewForcedReveal;
        UpdateLivePreview(SettingsService.Load());
    }

    private void ShowPracticePad_Click(object sender, RoutedEventArgs e)
    {
        InitiationSectionCard.Visibility = Visibility.Visible;
        ClosePracticeBtn.Visibility = Visibility.Visible;
        RenderGhostGuide();
    }

    private void HidePracticePad_Click(object sender, RoutedEventArgs e)
    {
        if (SettingsService.Load().LoreenVeilUnlocked)
        {
            InitiationSectionCard.Visibility = Visibility.Collapsed;
        }
    }

    private void RelockVeil_Click(object sender, RoutedEventArgs e)
    {
        var settings = SettingsService.Load();
        settings.LoreenVeilUnlocked = false;
        settings.LoreenVeilEnabled = false;
        SettingsService.Save(settings);

        _loading = true;
        ApplySettingsToUI(settings);
        SetupChallengeWord("LOREEN");
        _loading = false;
    }

    private void BuildCodexGrid()
    {
        CodexGrid.Children.Clear();
        foreach (var def in LoreenGlyphCatalog.AllGlyphs)
        {
            var card = new Border
            {
                Width = 160,
                Height = 110,
                Margin = new Thickness(0, 0, 10, 10),
                Padding = new Thickness(12, 10, 12, 10),
                CornerRadius = new CornerRadius(10),
                Background = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1)
            };

            var stack = new StackPanel { Spacing = 4 };
            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            top.Children.Add(new TextBlock
            {
                Text = def.Id.ToString(),
                FontFamily = LoreenVeilHelper.LoreenFont,
                FontSize = 28,
                Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF))
            });

            var badgePanel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right, Spacing = 2 };
            badgePanel.Children.Add(new TextBlock
            {
                Text = def.Id.ToString(),
                FontSize = 15,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Right
            });
            badgePanel.Children.Add(new TextBlock
            {
                Text = def.Origin == LoreenGlyphOrigin.Original ? "ORIGINAL" : "PATTERN",
                FontSize = 9,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = new SolidColorBrush(def.Origin == LoreenGlyphOrigin.Original
                    ? Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)
                    : Color.FromArgb(0xFF, 0xAF, 0x52, 0xDE)),
                HorizontalAlignment = HorizontalAlignment.Right
            });
            Grid.SetColumn(badgePanel, 1);
            top.Children.Add(badgePanel);

            stack.Children.Add(top);
            stack.Children.Add(new TextBlock
            {
                Text = def.Summary,
                FontSize = 10.5,
                Opacity = 0.72,
                TextWrapping = TextWrapping.Wrap,
                MaxLines = 2,
                TextTrimming = TextTrimming.CharacterEllipsis
            });

            card.Child = stack;
            var capturedChar = def.Id;
            card.Tapped += (_, __) =>
            {
                InitiationSectionCard.Visibility = Visibility.Visible;
                _challengeWord = capturedChar.ToString();
                _currentLetterIndex = 0;
                _completedIndices.Clear();
                _isCustomPracticeOnly = true;
                ClearUserStrokes();
                RenderChallengeHeader();
                RenderGhostGuide();
                RecognitionFeedbackText.Text = $"Loaded Loreen glyph '{capturedChar}' onto the Practice Pad.";
            };

            CodexGrid.Children.Add(card);
        }
    }
}
