plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.bagdar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.bagdar"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    androidResources {
        noCompress += listOf("tflite", "bin", "param")
    }

    packaging {
        jniLibs {
            excludes += listOf(
                "**/x86_64/**",
                "**/x86/**",
                "**/armeabi-v7a/**",
            )
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.ar:core:1.42.0")
}
