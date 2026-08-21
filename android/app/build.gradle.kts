import java.io.File
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val secretsPropertiesFile = rootProject.file("../secrets/gradle.properties")
val legacyKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeystorePropertiesFile =
    listOf(secretsPropertiesFile, legacyKeyPropertiesFile).firstOrNull { it.exists() }
val releaseKeystoreProperties = Properties().apply {
    if (releaseKeystorePropertiesFile != null) {
        releaseKeystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun Properties.releaseProperty(vararg names: String): String? =
    names.asSequence()
        .mapNotNull { getProperty(it)?.trim()?.takeIf(String::isNotEmpty) }
        .firstOrNull()

fun resolveReleaseStoreFile(path: String, propertiesFile: File?): File {
    val explicitFile = File(path)
    if (explicitFile.isAbsolute) {
        return explicitFile
    }

    val candidates =
        buildList {
            if (propertiesFile != null) {
                add(File(propertiesFile.parentFile, path))
            }
            add(project.file(path))
            add(rootProject.file(path))
            add(rootProject.file("../$path"))
        }

    return candidates.firstOrNull { it.exists() } ?: candidates.first()
}

val releaseStoreFile =
    releaseKeystoreProperties.releaseProperty("storeFile", "MYAPP_UPLOAD_STORE_FILE")
val releaseKeyAlias =
    releaseKeystoreProperties.releaseProperty("keyAlias", "MYAPP_UPLOAD_KEY_ALIAS")
val releaseStorePassword =
    releaseKeystoreProperties.releaseProperty("storePassword", "MYAPP_UPLOAD_STORE_PASSWORD")
val releaseKeyPassword =
    releaseKeystoreProperties.releaseProperty("keyPassword", "MYAPP_UPLOAD_KEY_PASSWORD")
val hasReleaseKeystore =
    listOf(
        releaseStoreFile,
        releaseKeyAlias,
        releaseStorePassword,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

android {
    namespace = "com.androidircx.flutter"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.androidircx.flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = checkNotNull(releaseKeyAlias)
                keyPassword = checkNotNull(releaseKeyPassword)
                storeFile = resolveReleaseStoreFile(
                    checkNotNull(releaseStoreFile),
                    releaseKeystorePropertiesFile,
                )
                storePassword = checkNotNull(releaseStorePassword)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
