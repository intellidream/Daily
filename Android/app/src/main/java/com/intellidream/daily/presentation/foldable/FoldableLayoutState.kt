package com.intellidream.daily.presentation.foldable

import com.intellidream.daily.designsystem.NavigationTab
import com.intellidream.daily.model.NewsArticle

/**
 * Represents the active target displayed in the secondary / detail pane
 * of the adaptive dual-pane foldable layout on expanded displays (e.g. Galaxy Z Fold 8, Pixel 9 Pro Fold).
 */
sealed class FoldableDetailTarget {
    /** Default persistent companion view showing live vitals pulse, morning briefing summary, and quick cards */
    data object Companion : FoldableDetailTarget()

    /** Full functional Hub embedded in the right pane */
    data class Hub(val tab: NavigationTab) : FoldableDetailTarget()

    /** User settings view embedded in the right pane */
    data object Settings : FoldableDetailTarget()

    /** Dashboard widget customization embedded in the right pane */
    data object Customize : FoldableDetailTarget()

    /** Dedicated Smart Briefing console with audio TTS controls in the right pane */
    data object Briefing : FoldableDetailTarget()

    /** Distraction-free article reader mode in the right pane */
    data class NewsArticleDetail(val article: NewsArticle) : FoldableDetailTarget()
}
