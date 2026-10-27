# ProGuard / R8 Rules for Daily WearOS

# Keep Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.SerializationKt
-keepclassmembers class * {
    *** Companion;
}
-keepclasseswithmembers class * {
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
    @kotlinx.serialization.Serializable class *;
}

# Keep WearOS Domain and Data models
-keep class com.intellidream.daily.wearos.domain.model.** { *; }
-keep class com.intellidream.daily.wearos.data.PendingSyncItem { *; }
-keep class com.intellidream.daily.wearos.data.SyncActionType { *; }
-keep class com.intellidream.daily.wearos.data.OfflineSyncManager { *; }

# Supabase and Ktor
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-dontwarn kotlinx.coroutines.**

# Horologist & Wear Compose
-keep class com.google.android.horologist.** { *; }
-keep class androidx.wear.compose.** { *; }
