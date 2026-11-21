import java.util.Properties

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.jetbrains.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun localProp(key: String): String =
    localProperties.getProperty(key, "").replace("\"", "\\\"")

android {
    namespace = "com.intellidream.daily.network"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        buildConfigField("String", "MICROSOFT_CLIENT_ID", "\"${localProp("MICROSOFT_CLIENT_ID")}\"")
        buildConfigField("String", "GOOGLE_MOBILE_CLIENT_ID", "\"${localProp("GOOGLE_MOBILE_CLIENT_ID")}\"")
        buildConfigField("String", "GOOGLE_DESKTOP_CLIENT_ID", "\"${localProp("GOOGLE_DESKTOP_CLIENT_ID")}\"")
        buildConfigField("String", "GOOGLE_DESKTOP_CLIENT_SECRET", "\"${localProp("GOOGLE_DESKTOP_CLIENT_SECRET")}\"")
    }
    buildFeatures {
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core-model"))
    api(libs.supabase.postgrest)
    api(libs.supabase.auth)
    api(libs.supabase.realtime)
    api(libs.supabase.functions)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.multiplatform.settings)
    implementation(libs.multiplatform.settings.coroutines)
    testImplementation(libs.junit)
}
