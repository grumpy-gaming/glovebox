plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.glovebox"
    // API 35 is the stable target for Pixel 9 / Android 15
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required for modern notification features
        isCoreLibraryDesugaringEnabled = true 
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.glovebox"
        
        // Supports modern plugins while staying compatible
        minSdk = flutter.minSdkVersion 
        targetSdk = 35 
        
        // Essential for apps using multiple high-end plugins
        multiDexEnabled = true 

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Provides "Desugaring" (translation) for Java 8+ features like time/dates
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
