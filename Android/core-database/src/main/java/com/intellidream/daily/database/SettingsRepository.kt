package com.intellidream.daily.database

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.intellidream.daily.model.AppSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "daily_settings")

class SettingsRepository(
    private val context: Context,
    private val coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        isLenient = true
    }

    private val settingsKey = stringPreferencesKey("daily_app_settings_json")

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    init {
        coroutineScope.launch {
            context.settingsDataStore.data
                .map { prefs ->
                    val rawJson = prefs[settingsKey]
                    if (!rawJson.isNullOrEmpty()) {
                        try {
                            json.decodeFromString<AppSettings>(rawJson)
                        } catch (e: Exception) {
                            AppSettings()
                        }
                    } else {
                        AppSettings()
                    }
                }
                .collect { loaded ->
                    _settings.value = loaded
                }
        }
    }

    suspend fun updateSettings(transform: (AppSettings) -> AppSettings) {
        context.settingsDataStore.edit { prefs ->
            val current = _settings.value
            val updated = transform(current)
            prefs[settingsKey] = json.encodeToString(updated)
            _settings.value = updated
        }
    }

    suspend fun getLatest(): AppSettings {
        val raw = context.settingsDataStore.data.first()[settingsKey]
        return if (!raw.isNullOrEmpty()) {
            try {
                json.decodeFromString(raw)
            } catch (e: Exception) {
                AppSettings()
            }
        } else {
            AppSettings()
        }
    }
}
