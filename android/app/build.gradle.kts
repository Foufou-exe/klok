import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature release — les secrets vivent dans android/key.properties, qui est
// gitignoré. Voir android/key.properties.example pour le gabarit et le README
// pour la commande keytool. Sans ce fichier on retombe sur les clés debug pour
// que `flutter run --release` continue de marcher en local, mais un APK ainsi
// signé NE DOIT PAS être distribué : la keystore debug change de machine en
// machine, et Android refuse une mise à jour dont la signature diffère.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "fr.foufou.klok"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Gravé : changer cet ID après une première installation force une
        // désinstallation (donc la perte de la base) sur la tablette.
        applicationId = "fr.foufou.klok"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "\n⚠️  klok : android/key.properties introuvable — build release " +
                        "signé avec les clés DEBUG. Ne distribue pas cet APK.\n"
                )
                signingConfigs.getByName("debug")
            }
            // Pas de minify/shrink : `printing` et `pdf` chargent des classes
            // par réflexion, et on n'a pas de banc de test release pour valider
            // des règles ProGuard. À réévaluer si la taille de l'APK devient un
            // problème.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
