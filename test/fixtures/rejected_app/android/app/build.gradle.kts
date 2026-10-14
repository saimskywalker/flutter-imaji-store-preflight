plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.rejected_app"
    defaultConfig {
        applicationId = "com.example.rejected_app"
        minSdk = 24
        targetSdk = 34
    }
}
