import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun signingProperties(fileName: String): Properties = Properties().apply {
    val propertiesFile = rootProject.file(fileName)
    if (propertiesFile.isFile) propertiesFile.reader(Charsets.UTF_8).use { load(it) }
}

fun Properties.hasSigningCredentials(): Boolean =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !getProperty(it).isNullOrBlank() }

val debugKey = signingProperties("pol-debug.properties")
val releaseKey = signingProperties("key.properties")
val releaseKeyConfigured = releaseKey.hasSigningCredentials()
val releaseKeystoreExists = releaseKey.getProperty("storeFile")?.let { file(it).isFile } == true

val verifyReleaseSigning = tasks.register("verifyPolReleaseSigning") {
    doLast {
        check(releaseKeyConfigured && releaseKeystoreExists) {
            "Release signing requires a keystore and all four fields in android/key.properties."
        }
    }
}

android {
    namespace = "com.arman.firefoxvpn"
    compileSdk = flutter.compileSdkVersion
    // The NDK installed here (Flutter's default, 28.x, is not).
    ndkVersion = "30.0.16248370"

    // The native libraries (the Go core, Flutter's engine, the app's code)
    // are compressed inside the APK, as zip files are: a third of the
    // download (33 MB to about 14 MB for arm64). Android unpacks them when it
    // installs the app, which takes a little more room on the phone. The
    // files themselves do not change.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // hev-socks5-tunnel, which the VPN runs (Tun2Socks.kt).
    externalNativeBuild {
        ndkBuild {
            path = file("../hev-socks5-tunnel/Android.mk")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.polvpn.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The core's aar is built for API 24 (gomobile bind -androidapi 24).
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            ndkBuild {
                targets += "hev-socks5-tunnel"
                // REV_ID: its version, which it would ask Git for.
                arguments += listOf("REV_ID=2.19.3", "APP_SUPPORT_FLEXIBLE_PAGE_SIZES=true")
                // The class its native methods bind to.
                cFlags += listOf("-O3", "-DPKGNAME=com/arman/firefoxvpn", "-DCLSNAME=Tun2Socks")
            }
        }
    }

    signingConfigs {
        if (rootProject.file("pol-debug.properties").isFile) {
            require(debugKey.hasSigningCredentials()) {
                "android/pol-debug.properties must specify all four signing fields."
            }
            getByName("debug") {
                storeFile = file(debugKey.getProperty("storeFile"))
                storePassword = debugKey.getProperty("storePassword")
                keyAlias = debugKey.getProperty("keyAlias")
                keyPassword = debugKey.getProperty("keyPassword")
            }
        }
        create("release") {
            if (releaseKeyConfigured) {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Flutter's plugin points CMake at an empty project, to make the Android plugin
// download the NDK, unless it sees a CMake build or `flutter build` found the NDK
// installed (so `gradlew` and Android Studio get it); two native builds are refused.
androidComponents {
    finalizeDsl { it.externalNativeBuild.cmake.path = null }
    onVariants(selector().withBuildType("release")) { variant ->
        val preBuild = "pre${variant.name.replaceFirstChar { it.uppercaseChar() }}Build"
        tasks.matching { it.name == preBuild }.configureEach { dependsOn(verifyReleaseSigning) }
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

dependencies {
    // The Go core: `gomobile bind -target=android -androidapi 24
    // -o app/android/app/libs/core.aar ./mobile` in core/ (see app/README.md).
    implementation(files("libs/core.aar"))
    // ProxyController: the browser sign-in's WebView uses the core's
    // sign-in proxy. The version webview_flutter_android itself uses.
    implementation("androidx.webkit:webkit:1.15.0")
}
