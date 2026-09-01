import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci penandatanganan RILIS — opsional & TIDAK ikut ke git.
//
// Selama `android/key.properties` belum dibuat, APK rilis tetap ditandatangani
// kunci DEBUG seperti sebelumnya (perilaku lama, tidak ada yang rusak). Begitu
// pemilik membuat keystore sendiri dan mengisi file itu, build rilis otomatis
// memakainya.
//
// Isi android/key.properties (JANGAN di-commit):
//   storeFile=C:/kunci/maspart-release.jks
//   storePassword=...
//   keyAlias=maspart
//   keyPassword=...
// Membuat keystore:
//   keytool -genkey -v -keystore maspart-release.jks -keyalg RSA //           -keysize 2048 -validity 10000 -alias maspart
// ⚠️ Setelah beralih ke kunci baru, pengguna yang sudah memasang APK
//    lama HARUS meng-uninstall dulu — Android menolak update beda kunci.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.maspart_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.maspart_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Kunci rilis bila key.properties ada; kalau tidak, tetap kunci debug
            // (perilaku lama) supaya `flutter build apk --release` tak gagal.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
