plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.clean_app"
    defaultConfig {
        applicationId = "com.example.clean_app"
        minSdk = 24
        targetSdk = 36
    }
}
