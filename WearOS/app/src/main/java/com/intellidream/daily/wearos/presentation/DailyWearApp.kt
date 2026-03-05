package com.intellidream.daily.wearos.presentation

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalContext
import androidx.wear.compose.material.MaterialTheme
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.bubbles.BubblesScreen
import com.intellidream.daily.wearos.presentation.pairing.PairingScreen
import com.intellidream.daily.wearos.presentation.smokes.SmokesScreen
import com.intellidream.daily.wearos.presentation.theme.DailyWearTheme

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DailyWearApp() {
    val context = LocalContext.current
    val sessionManager = remember { WatchSessionManager(context) }
    val isAuthenticated by sessionManager.isAuthenticated.collectAsState()
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
                val pagerState = rememberPagerState(pageCount = { 2 })
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize()
                ) { page ->
                    when (page) {
                        0 -> BubblesScreen(sessionManager)
                        1 -> SmokesScreen(sessionManager)
                    }
                }
            } else {
                PairingScreen(sessionManager)
            }
        }
    }
}
