package com.arman.firefoxvpn

import android.Manifest
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.OpenableColumns
import android.service.quicksettings.TileService
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject

/**
 * The Flutter UI. Channel "app/android": dataDir, startCore (with the proxy
 * off), setOn, isRunning, openUrl. The UI talks to the core itself through
 * its HTTP API on loopback, as on the desktop.
 */
class MainActivity : FlutterActivity() {
    private var androidChannel: MethodChannel? = null
    private var tunnelTestChannel: MethodChannel? = null
    // Reopening the Activity only reports restoration after decrypting the stored session.
    private var createdTestSessionHere = false
    private var fixturePowerRequest = 0L
    /** Waits for the user's answer to the VPN permission. */
    private var pendingOn: Result? = null
    // A backup waiting for the place the user picks to save it.
    private var pendingSave: Pair<ByteArray, Result>? = null
    // A backup being picked to open.
    private var pendingOpen: Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        holdPhoneUpright(resources.configuration)
        super.onCreate(savedInstanceState)
        removeOtherCards()
    }

    /** A tile long-press returns an already open UI to its home page. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == TileService.ACTION_QS_TILE_PREFERENCES) {
            androidChannel?.invokeMethod("openHome", null)
        }
    }

    /**
     * One card in the recent apps. A card stays there after Back, and with no
     * task affinity (the manifest's, against task hijacking) Android keeps it
     * beside a new task opened with another intent: from the notification,
     * the tile, the widget, or the installer's Open.
     */
    private fun removeOtherCards() {
        for (task in getSystemService(ActivityManager::class.java).appTasks) {
            try {
                @Suppress("DEPRECATION") // taskId came only with Android 10.
                if (task.taskInfo.persistentId != taskId) task.finishAndRemoveTask()
            } catch (e: IllegalArgumentException) {
                // That task went by itself meanwhile.
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        holdPhoneUpright(newConfig)
    }

    /**
     * A phone stays upright (its layout is made for it); a tablet, whose
     * shorter side is 600 dp or more, turns freely. Asked again when the
     * screen changes, so a foldable follows its folding. A TV (960 x 540 dp,
     * so "short" too) cannot turn: it keeps its own orientation.
     */
    private fun holdPhoneUpright(config: Configuration) {
        val wanted = if (config.smallestScreenWidthDp < 600 && !isTv(config)) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        if (requestedOrientation != wanted) requestedOrientation = wanted
    }

    /** Whether this is a TV (Android TV, Google TV), worked with a remote. */
    private fun isTv(config: Configuration) =
        config.uiMode and Configuration.UI_MODE_TYPE_MASK == Configuration.UI_MODE_TYPE_TELEVISION

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/android")
        androidChannel = channel
        val tunnelTest = CoreService.tunnelTestEnabled(this)
        if (tunnelTest) configureTunnelTest(flutterEngine)
        channel.setMethodCallHandler { call, result ->
            if (tunnelTest && call.method !in FIXTURE_ANDROID_METHODS) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            when (call.method) {
                "dataDir" -> result.success(CoreService.dataDir(this).absolutePath)
                "startCore" -> result.success(CoreService.startCore(this, on = false))
                "dashboardAddress" -> result.success(mobile.Mobile.dashboardAddress())
                "setOn" -> {
                    val on = call.argument<Boolean>("on") == true
                    if (tunnelTest && on) {
                        val request = ++fixturePowerRequest
                        tunnelTestWork(result) {
                            val ready = TunnelTestSession.exists(this)
                            main.post {
                                if (request != fixturePowerRequest || isFinishing) {
                                    result.error("vpn_denied", "The VPN permission request was canceled.", null)
                                } else if (ready) requestVpnPower(true, result)
                                else result.error("session_required", "Create a local test session first.", null)
                            }
                        }
                    } else {
                        requestVpnPower(on, result)
                    }
                }
                "isRunning" -> result.success(if (tunnelTest) CoreService.tunnelTestEstablished else mobile.Mobile.running())
                "connectionMode" -> result.success(if (tunnelTest) CoreService.MODE_VPN else CoreService.connectionMode(this))
                "showSpeed" -> result.success(CoreService.showSpeed(this))
                "setShowSpeed" -> {
                    CoreService.setShowSpeed(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "routingEnabled" -> result.success(CoreService.routingEnabled(this))
                "setRoutingEnabled" -> {
                    CoreService.setRoutingEnabled(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "setConnectionMode" -> {
                    val mode = call.argument<String>("mode") ?: CoreService.MODE_VPN
                    // A running proxy switched to the VPN needs the permission
                    // first; the app turns it off and on again to ask.
                    if (CoreService.on && mode == CoreService.MODE_VPN && VpnService.prepare(this) != null) {
                        result.error("vpn_denied", "the VPN is not allowed yet", null)
                    } else {
                        CoreService.setConnectionMode(this, mode)
                        result.success(null)
                    }
                }
                "installedApps" -> inBackground(result) { installedApps() }
                "appIcon" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    inBackground(result) { appIcon(pkg) }
                }
                "appRouting" -> inBackground(result) {
                    // The page shows the region's apps installed since the
                    // last look checked; the VPN takes them at once.
                    if (CoreService.appMode(this) == CoreService.MODE_EXCLUDE &&
                        CoreService.suggest(this, force = true)
                    ) {
                        CoreService.reconnect(this)
                    }
                    mapOf(
                        "mode" to CoreService.appMode(this),
                        "bypass" to CoreService.appSet(this, CoreService.BYPASS).toList(),
                        "only" to CoreService.appSet(this, CoreService.ONLY).toList(),
                        "declined" to CoreService.appSet(this, CoreService.DECLINED).toList(),
                        "region" to CoreService.regionAppList(),
                    )
                }
                "setAppRouting" -> {
                    fun set(key: String) = (call.argument<List<String>>(key) ?: emptyList()).toSet()
                    CoreService.setAppRouting(
                        this,
                        call.argument<String>("mode") ?: CoreService.MODE_EXCLUDE,
                        mapOf(
                            CoreService.BYPASS to set("bypass"),
                            CoreService.ONLY to set("only"),
                            CoreService.DECLINED to set("declined"),
                        ),
                    )
                    if (call.argument<Boolean>("apply") == true) CoreService.reconnect(this)
                    result.success(null)
                }
                // The browser sign-in's WebView goes through the core's
                // sign-in proxy (an address), or straight out again (null).
                // The override covers every WebView of this app, and takes
                // effect once the callback runs.
                "setWebViewProxy" -> {
                    if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val address = call.argument<String>("address")
                    val proxies = ProxyController.getInstance()
                    val done = Runnable { result.success(true) }
                    val onMain = Executor { main.post(it) }
                    if (address.isNullOrEmpty()) {
                        proxies.clearProxyOverride(onMain, done)
                    } else {
                        proxies.setProxyOverride(
                            ProxyConfig.Builder().addProxyRule(address).build(),
                            onMain,
                            done,
                        )
                    }
                }
                // Saves a file (a backup) where the user picks, with the
                // system's own dialog: no storage permission. Answers the
                // file's name, or null when the user backs out.
                "saveFile" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || (tunnelTest && bytes.size !in 1..MAX_TEST_REPORT_BYTES)) {
                        result.error("no_data", "nothing to save", null)
                        return@setMethodCallHandler
                    }
                    pendingSave?.second?.success(null)
                    pendingSave = bytes to result
                    val create = Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                    if (tunnelTest) {
                        create.setType("text/plain")
                            .putExtra(Intent.EXTRA_TITLE, "pol-vpn-diagnostics.txt")
                            .putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    } else {
                        create.setType(call.argument<String>("mime") ?: "application/octet-stream")
                            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup")
                    }
                    try {
                        startActivityForResult(create, SAVE_REQUEST)
                    } catch (e: ActivityNotFoundException) {
                        pendingSave = null
                        result.error("no_picker", "this device has no file picker", null)
                    }
                }
                // Opens a file (a backup) the user picks, with the system's
                // own dialog, and answers its bytes, or null when the user
                // backs out. It reads to the end: the size a provider
                // reports can be wrong (0 for a file written through it).
                "openFile" -> {
                    pendingOpen?.success(null)
                    pendingOpen = result
                    val open = Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*")
                        .putExtra(Intent.EXTRA_MIME_TYPES, call.argument<List<String>>("mimes")?.toTypedArray())
                    try {
                        startActivityForResult(open, OPEN_REQUEST)
                    } catch (e: ActivityNotFoundException) {
                        pendingOpen = null
                        result.error("no_picker", "this device has no file picker", null)
                    }
                }
                // The phone's main processor type (arm64-v8a, armeabi-v7a, ...).
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                "isTv" -> result.success(isTv(resources.configuration))
                "routingCountries" -> inBackground(result) { routingCountries() }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    val view = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    try {
                        // A TV without a browser does not throw: its stub
                        // "browser" only shows Android's "no app" message.
                        val handlers = packageManager.queryIntentActivities(view, 0)
                            .filter { it.activityInfo.packageName != "com.android.tv.frameworkpackagestubs" }
                        if (handlers.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        startActivity(view)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun configureTunnelTest(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pol/tunnel_fixture")
        tunnelTestChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceInfo" -> result.success(
                    mapOf(
                        "androidVersion" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                        "architecture" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "Unknown"),
                    ),
                )
                "state" -> tunnelTestWork(result) {
                    val stored = runCatching { TunnelTestSession.exists(this) }
                    val ready = stored.getOrDefault(false)
                    val rawState = if (ready) CoreService.tunnelTestCoreStatus() else ""
                    val state = if (rawState.isEmpty()) JSONObject() else JSONObject(rawState)
                    val established = CoreService.tunnelTestEstablished
                    val stopping = CoreService.tunnelTestStopping
                    val connected = state.optBoolean("connected") && established
                    val failure = when {
                        stored.isFailure -> "session_store_unavailable"
                        CoreService.tunnelTestFailure.isNotEmpty() -> CoreService.tunnelTestFailure
                        else -> state.optString("failureCode").takeIf { it in FIXTURE_CORE_FAILURES }.orEmpty()
                    }
                    val status = mapOf(
                        "enabled" to true,
                        "sessionReady" to ready,
                        "sessionRestored" to (ready && !createdTestSessionHere),
                        "tokenRefreshed" to state.optBoolean("tokenRefreshed"),
                        "proxyAuthorized" to state.optBoolean("proxyAuthorized"),
                        "vpnEstablished" to established,
                        "connected" to connected,
                        "connecting" to (CoreService.on && !connected && failure.isEmpty()),
                        "disconnecting" to stopping,
                        "requests" to state.optLong("requests"),
                        "bytesUp" to state.optLong("bytesUp"),
                        "bytesDown" to state.optLong("bytesDown"),
                        "quotaLimit" to state.optLong("quotaLimit").takeUnless { state.isNull("quotaLimit") },
                        "quotaRemaining" to state.optLong("quotaRemaining").takeUnless { state.isNull("quotaRemaining") },
                        "sessionRenewed" to state.optBoolean("sessionRenewed"),
                        "renewals" to state.optLong("renewals"),
                        "failure" to failure,
                    )
                    main.post { result.success(status) }
                }
                "signIn" -> tunnelTestWork(result) {
                    if (TunnelTestSession.create(this)) {
                        createdTestSessionHere = true
                        CoreService.clearTunnelTestStatus()
                    }
                    main.post { result.success(true) }
                }
                "signOut" -> {
                    cancelPendingVpn()
                    CoreService.turnOff(this)
                    CoreService.clearTunnelTestStatus()
                    tunnelTestWork(result) {
                        TunnelTestSession.clear(this)
                        createdTestSessionHere = false
                        main.post { result.success(true) }
                    }
                }
                "renewSession" -> tunnelTestWork(result) {
                    check(CoreService.tunnelTestEstablished)
                    mobile.Mobile.renewTunnelTest()
                    main.post { result.success(true) }
                }
                "openProbe" -> result.success(openTunnelTestPage())
                else -> result.notImplemented()
            }
        }
    }

    private fun openTunnelTestPage(): Boolean {
        if (!CoreService.tunnelTestEstablished) return false
        val view = Intent(Intent.ACTION_VIEW, Uri.parse(CoreService.TUNNEL_TEST_URL))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        return try {
            startActivity(view)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun tunnelTestWork(result: Result, work: () -> Unit) {
        worker.execute {
            try {
                work()
            } catch (_: Exception) {
                main.post { result.error("fixture_unavailable", "The local tunnel test could not complete.", null) }
            } catch (_: LinkageError) {
                main.post { result.error("fixture_unavailable", "The local tunnel test could not complete.", null) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun requestVpnPower(on: Boolean, result: Result) {
        if (!on) {
            cancelPendingVpn()
            CoreService.turnOff(this)
            result.success(null)
            return
        }
        val tunnelTest = CoreService.tunnelTestEnabled(this)
        if (!tunnelTest) askForNotifications()
        // First use goes through Android's own permission dialog.
        val consent = if (tunnelTest || CoreService.usesVpn(this)) VpnService.prepare(this) else null
        if (consent == null) {
            turnOn(result)
        } else {
            cancelPendingVpn()
            pendingOn = result
            try {
                startActivityForResult(consent, VPN_REQUEST)
            } catch (_: RuntimeException) {
                cancelPendingVpn()
            }
        }
    }

    private fun cancelPendingVpn() {
        fixturePowerRequest++
        val pending = pendingOn ?: return
        pendingOn = null
        pending.error("vpn_denied", "The VPN permission request was canceled.", null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        androidChannel?.setMethodCallHandler(null)
        androidChannel = null
        tunnelTestChannel?.setMethodCallHandler(null)
        tunnelTestChannel = null
        cancelPendingVpn()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Country codes for first-run routing; no phone or location permissions. */
    private fun routingCountries(): Map<String, String> {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
            return emptyMap()
        }
        val service = getSystemService(TelephonyManager::class.java) ?: return emptyMap()
        // On dual-SIM devices use the subscription selected for mobile data.
        val phone = runCatching {
            val subscription = SubscriptionManager.getDefaultDataSubscriptionId()
            if (subscription >= 0) {
                service.createForSubscriptionId(subscription)
            } else {
                service
            }
        }.getOrDefault(service)
        return mapOf(
            "network_country" to runCatching { phone.networkCountryIso ?: "" }.getOrDefault(""),
            "sim_country" to runCatching { phone.simCountryIso ?: "" }.getOrDefault("")
        )
    }

    /** Runs [work] off the UI thread and answers with its value. */
    private fun inBackground(result: Result, work: () -> Any?) {
        worker.execute {
            val value = try {
                work()
            } catch (e: Exception) {
                null
            }
            main.post { result.success(value) }
        }
    }

    /**
     * The installed apps but this one: package, name, and whether it has a
     * launcher icon, on a phone's home screen or a TV's (the others are
     * mostly the system's). Packages without code (overlays, resources) use
     * no network and are left out.
     */
    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val withIcon = listOf(Intent.CATEGORY_LAUNCHER, Intent.CATEGORY_LEANBACK_LAUNCHER)
            .flatMap { pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(it), 0) }
            .map { it.activityInfo.packageName }
            .toSet()
        @Suppress("DEPRECATION")
        return pm.getInstalledApplications(0)
            .filter { it.packageName != packageName && (it.flags and ApplicationInfo.FLAG_HAS_CODE) != 0 }
            .map {
                mapOf(
                    "package" to it.packageName,
                    "label" to it.loadLabel(pm).toString(),
                    "launcher" to (it.packageName in withIcon),
                )
            }
    }

    /** An app's icon as a small PNG. */
    private fun appIcon(pkg: String): ByteArray {
        val drawable = packageManager.getApplicationIcon(pkg)
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun turnOn(result: Result) {
        try {
            CoreService.turnOn(this)
            if (CoreService.tunnelTestEnabled(this)) askForNotifications()
            result.success(null)
        } catch (e: Exception) {
            val message = if (CoreService.tunnelTestEnabled(this)) "The local test tunnel could not start." else e.message
            result.error("start_failed", message, null)
        }
    }

    @Deprecated("The VPN permission is asked with startActivityForResult.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_REQUEST) {
            saved(resultCode, data?.data)
            return
        }
        if (requestCode == OPEN_REQUEST) {
            opened(resultCode, data?.data)
            return
        }
        if (requestCode != VPN_REQUEST) return
        val result = pendingOn ?: return
        pendingOn = null
        if (resultCode == RESULT_OK) turnOn(result) else result.error("vpn_denied", "the VPN was not allowed", null)
    }

    /** Writes the pending file to [uri], the place the user picked. */
    private fun saved(resultCode: Int, uri: Uri?) {
        val (bytes, result) = pendingSave ?: return
        pendingSave = null
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val tunnelTest = CoreService.tunnelTestEnabled(this)
        if (tunnelTest && uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("write_failed", "Android could not save the diagnostic report.", null)
            return
        }
        worker.execute {
            val name = try {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                    ?: throw IllegalStateException("the file could not be opened")
                displayName(uri)
            } catch (e: Exception) {
                val message = if (tunnelTest) "Android could not save the diagnostic report." else e.message
                main.post { result.error("write_failed", message, null) }
                return@execute
            }
            main.post { result.success(name) }
        }
    }

    /** Reads the picked file at [uri], to the end. */
    private fun opened(resultCode: Int, uri: Uri?) {
        val result = pendingOpen ?: return
        pendingOpen = null
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        worker.execute {
            val bytes = try {
                contentResolver.openInputStream(uri)?.use { input ->
                    val out = ByteArrayOutputStream()
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        // A backup is a few kilobytes; nothing sensible is this big.
                        if (out.size() > MAX_OPEN_BYTES) throw IllegalStateException("the file is too large")
                    }
                    out.toByteArray()
                } ?: throw IllegalStateException("the file could not be opened")
            } catch (e: Exception) {
                main.post { result.error("read_failed", e.message, null) }
                return@execute
            }
            main.post { result.success(bytes) }
        }
    }

    private fun displayName(uri: Uri): String =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: uri.lastPathSegment ?: ""

    override fun onDestroy() {
        // Off, nothing needs the core once the UI is gone.
        if (CoreService.tunnelTestEnabled(this)) {
            worker.shutdown()
        } else if (isFinishing && !CoreService.on) {
            CoreService.stopCore()
        }
        super.onDestroy()
    }

    companion object {
        private const val VPN_REQUEST = 7
        private const val SAVE_REQUEST = 8
        private const val OPEN_REQUEST = 9
        private const val MAX_OPEN_BYTES = 16 * 1024 * 1024
        private const val MAX_TEST_REPORT_BYTES = 64 * 1024
        private val FIXTURE_ANDROID_METHODS = setOf("setOn", "isRunning", "connectionMode", "abi", "isTv", "saveFile")
        private val FIXTURE_CORE_FAILURES = setOf(
            "fixture_core_stopped", "fixture_status_failed", "fixture_connection_failed",
        )
    }

    /** The service's notification needs this on Android 13 and later. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
