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

# Keep WearOS Domain, Data and Presentation models
-keep class com.intellidream.daily.wearos.domain.model.** { *; }
-keep class com.intellidream.daily.wearos.domain.util.** { *; }
-keep class com.intellidream.daily.wearos.data.** { *; }
-keep class com.intellidream.daily.wearos.presentation.orbit.** { *; }
-keep class com.intellidream.daily.wearos.presentation.components.** { *; }
-keep class com.intellidream.daily.wearos.presentation.tagdos.** { *; }
-keep class com.intellidream.daily.wearos.presentation.pulse.** { *; }

# Supabase and Ktor
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-dontwarn kotlinx.coroutines.**

# Horologist & Wear Compose
-keep class com.google.android.horologist.** { *; }
-keep class androidx.wear.compose.** { *; }
