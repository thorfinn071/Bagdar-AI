plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val splitApksByAbi = project.findProperty("split-per-abi")?.toString() == "true"

android {
    namespace = "com.example.bagdar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    flavorDimensions += "bagdar"
    productFlavors {
        create("core") {
            dimension = "bagdar"
            isDefault = true
        }
        create("research") {
            dimension = "bagdar"
        }
        create("simulation") {
            dimension = "bagdar"
            applicationIdSuffix = ".simulation"
            versionNameSuffix = "-simulation"
        }
    }

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
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Flutter supplies ABI splits; AGP rejects combining them with ndk filters.
            if (!splitApksByAbi) {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
            }
        }
    }

    androidResources {
        noCompress += listOf("tflite", "bin", "param")
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
    // Same local Vosk runtime already used by vosk_flutter_2; no new network ASR.
    implementation("com.alphacephei:vosk-android:0.3.47@aar")
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    testImplementation("junit:junit:4.13.2")
    implementation("com.google.ar:core:1.42.0")
}
