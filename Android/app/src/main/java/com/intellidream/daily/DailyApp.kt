package com.intellidream.daily

import android.app.Application
import com.intellidream.daily.database.SettingsRepository
import com.intellidream.daily.network.AuthRepository

class DailyApp : Application() {
    lateinit var settingsRepository: SettingsRepository
        private set
    lateinit var authRepository: AuthRepository
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        settingsRepository = SettingsRepository(this)
        authRepository = AuthRepository()
    }

    companion object {
        lateinit var instance: DailyApp
            private set
    }
}
