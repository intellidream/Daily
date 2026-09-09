package com.intellidream.daily.wearos.presentation

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.wear.compose.foundation.ExperimentalWearFoundationApi
import androidx.wear.compose.foundation.HierarchicalFocusCoordinator
import androidx.wear.compose.material.MaterialTheme
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.about.AboutScreen
import com.intellidream.daily.wearos.presentation.bubbles.Bubbles7DaysScreen
import com.intellidream.daily.wearos.presentation.bubbles.BubblesScreen
import com.intellidream.daily.wearos.presentation.pairing.PairingScreen
import com.intellidream.daily.wearos.presentation.smokes.Smokes7DaysScreen
import com.intellidream.daily.wearos.presentation.smokes.SmokesScreen
import com.intellidream.daily.wearos.presentation.theme.DailyWearTheme

@OptIn(ExperimentalFoundationApi::class, ExperimentalWearFoundationApi::class)
@Composable
fun DailyWearApp(targetPage: Int = -1) {
    val context = LocalContext.current
    val sessionManager = remember { WatchSessionManager.getInstance(context) }
    val isAuthenticated by sessionManager.isAuthenticated.collectAsState()
    val isPairing by sessionManager.isPairing.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                sessionManager.onAppResumed()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    DailyWearTheme {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colors.background)
        ) {
            if (isAuthenticated) {
                // Canonical 5-Page Horizontal Pager matching watchOS & ZeppOS
                val pagerState = rememberPagerState(
                    initialPage = if (targetPage in 0..4) targetPage else 0,
                    pageCount = { 5 }
                )

                LaunchedEffect(targetPage) {
                    if (targetPage in 0..4 && pagerState.currentPage != targetPage) {
                        pagerState.scrollToPage(targetPage)
                    }
                }

                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize()
                ) { page ->
                    val isPageActive = (pagerState.currentPage == page)
                    HierarchicalFocusCoordinator(requiresFocus = { pagerState.currentPage == page && !pagerState.isScrollInProgress }) {
                        when (page) {
                            0 -> BubblesScreen(sessionManager, isPageActive = isPageActive)
                            1 -> Bubbles7DaysScreen(sessionManager, isPageActive = isPageActive)
                            2 -> SmokesScreen(sessionManager, isPageActive = isPageActive)
                            3 -> Smokes7DaysScreen(sessionManager, isPageActive = isPageActive)
                            4 -> AboutScreen(sessionManager, isPageActive = isPageActive)
                        }
                    }
                }
            } else {
                PairingScreen(sessionManager)
            }
        }
    }
}
