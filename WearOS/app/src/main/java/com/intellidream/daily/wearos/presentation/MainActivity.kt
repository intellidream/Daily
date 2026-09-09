package com.intellidream.daily.wearos.presentation

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableIntStateOf
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

class MainActivity : ComponentActivity() {
    private val targetPage = mutableIntStateOf(-1)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        val page = intent?.getIntExtra("page", -1) ?: -1
        targetPage.intValue = page
        setContent {
            DailyWearApp(targetPage = targetPage.intValue)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val page = intent.getIntExtra("page", -1)
        if (page != -1) {
            targetPage.intValue = page
        }
    }
}
