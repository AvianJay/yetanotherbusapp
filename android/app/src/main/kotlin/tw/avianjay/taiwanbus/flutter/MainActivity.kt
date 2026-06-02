package tw.avianjay.taiwanbus.flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var appLaunchChannel: MethodChannel? = null
    private var pendingLaunchPayload: Map<String, Any?>? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingBackgroundLocationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingLaunchPayload = AppLaunchConstants.extractLaunchPayload(intent)
        val wearSyncBridge = WearSyncBridge(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }

                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }

                "installApk" -> {
                    handleInstallApk(call, result)
                }

                else -> result.notImplemented()
            }
        }

        appLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LAUNCH_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialLaunchAction" -> {
                        result.success(pendingLaunchPayload)
                        pendingLaunchPayload = null
                    }

                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_INTEGRATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pinStopShortcut" -> {
                    result.success(requestPinnedStopShortcut(call))
                }

                "refreshFavoriteWidgets" -> {
                    FavoriteGroupWidgetSupport.requestRefreshAll(this)
                    result.success(null)
                }

                "setFavoriteWidgetAutoRefreshMinutes" -> {
                    val minutes = call.argument<Int>("minutes") ?: 0
                    FavoriteWidgetRefreshScheduler.sync(this, minutes)
                    result.success(null)
                }

                "setSmartRouteNotificationsEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    SmartRouteNotificationScheduler.sync(this, enabled)
                    result.success(null)
                }

                "setApplicationInForeground" -> {
                    val appInForeground = call.argument<Boolean>("appInForeground") ?: false
                    AppRuntimeStateStore.setAppInForeground(this, appInForeground)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WEAR_OS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (!wearSyncBridge.handle(call, result)) {
                result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WEAR_OS_EVENTS_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                WearEventBridge.attach(events)
            }

            override fun onCancel(arguments: Any?) {
                WearEventBridge.detach()
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRIP_MONITOR_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    requestNotificationPermission(result)
                }

                "requestBackgroundLocationPermission" -> {
                    requestBackgroundLocationPermission(result)
                }

                "startOrUpdateTripMonitor" -> {
                    val session = call.argument<Map<String, Any?>>("session")
                    if (session == null) {
                        result.error("missing_session", "Trip monitor session is required.", null)
                        return@setMethodCallHandler
                    }
                    RouteTripMonitorService.startOrUpdate(this, session)
                    result.success(null)
                }

                "setTripMonitorAppInForeground" -> {
                    val appInForeground = call.argument<Boolean>("appInForeground") ?: true
                    RouteTripMonitorService.setAppInForeground(this, appInForeground)
                    result.success(null)
                }

                "pauseTripMonitor" -> {
                    val session = call.argument<Map<String, Any?>>("session")
                    val reason = call.argument<String>("reason") ?: "user"
                    RouteTripMonitorService.pause(this, session, reason)
                    result.success(null)
                }

                "resumeTripMonitor" -> {
                    RouteTripMonitorService.resume(this)
                    result.success(null)
                }

                "isTripMonitorPaused" -> {
                    val session = call.argument<Map<String, Any?>>("session")
                    val parsedSession = session?.let { RouteTripMonitorService.parseSessionPayload(it) }
                    result.success(
                        parsedSession?.let { AppRuntimeStateStore.isTripMonitorPausedFor(this, it) }
                            ?: false,
                    )
                }

                "getTripMonitorPauseState" -> {
                    result.success(AppRuntimeStateStore.loadPausedTripMonitor(this)?.toMap())
                }

                "stopTripMonitor" -> {
                    RouteTripMonitorService.stop(this)
                    result.success(null)
                }

                "getAndroidDeviceInfo" -> {
                    result.success(getAndroidDeviceInfo())
                }

                "openNotificationChannelSettings" -> {
                    openNotificationChannelSettings()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = AppLaunchConstants.extractLaunchPayload(intent) ?: return
        pendingLaunchPayload = payload
        appLaunchChannel?.invokeMethod("onLaunchAction", payload)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_BACKGROUND_LOCATION) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            pendingBackgroundLocationPermissionResult?.success(
                if (granted) "granted" else "denied",
            )
            pendingBackgroundLocationPermissionResult = null
            return
        }
        if (requestCode != REQUEST_CODE_POST_NOTIFICATIONS) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openAppDetailsSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun handleInstallApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("missing_path", "APK path is required.", null)
            return
        }

        val apkFile = File(path)
        if (!apkFile.exists()) {
            result.error("missing_file", "APK file does not exist.", path)
            return
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile,
        )
        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = apkUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivity(installIntent)
        result.success(null)
    }

    private fun requestPinnedStopShortcut(call: MethodCall): Boolean {
        val provider = call.argument<String>("provider")?.trim().orEmpty()
        val routeKey = call.argument<Int>("routeKey")
        val pathId = call.argument<Int>("pathId")
        val stopId = call.argument<Int>("stopId")
        if (provider.isEmpty() || routeKey == null || pathId == null || stopId == null) {
            return false
        }

        val routeName = call.argument<String>("routeName")?.trim().orEmpty()
        val stopName = call.argument<String>("stopName")?.trim().orEmpty()
        val shortcutId = "stop_${provider}_${routeKey}_${pathId}_${stopId}"
        val shortLabel = when {
            stopName.isNotBlank() -> stopName
            routeName.isNotBlank() -> routeName
            else -> "YABus"
        }
        val longLabel = buildString {
            append(if (routeName.isNotBlank()) routeName else "Route $routeKey")
            if (stopName.isNotBlank()) {
                append(" - ")
                append(stopName)
            }
        }
        val intent = AppLaunchConstants.createRouteDetailIntent(
            context = this,
            provider = provider,
            routeKey = routeKey,
            pathId = pathId,
            stopId = stopId,
        ).apply {
            action = Intent.ACTION_VIEW
        }
        val shortcut = ShortcutInfoCompat.Builder(this, shortcutId)
            .setShortLabel(shortLabel.take(45))
            .setLongLabel(longLabel.take(100))
            .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(intent)
            .build()

        return ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingNotificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_POST_NOTIFICATIONS,
        )
    }

    private fun requestBackgroundLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("granted")
            return
        }
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            openAppDetailsSettings()
            result.success("opened_settings")
            return
        }

        pendingBackgroundLocationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            REQUEST_CODE_BACKGROUND_LOCATION,
        )
    }

    private fun getAndroidDeviceInfo(): Map<String, Any?> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "sdkVersion" to Build.VERSION.SDK_INT,
        )
    }

    private fun openNotificationChannelSettings() {
        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            putExtra(Settings.EXTRA_CHANNEL_ID, "trip_monitor")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    companion object {
        private const val UPDATE_INSTALLER_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/update_installer"
        private const val APP_LAUNCH_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/app_launch"
        private const val HOME_INTEGRATION_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/home_integration"
        private const val WEAR_OS_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/wear_os"
        private const val WEAR_OS_EVENTS_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/wear_os_events"
        private const val TRIP_MONITOR_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/trip_monitor"
        private const val REQUEST_CODE_BACKGROUND_LOCATION = 900
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 901
    }
}
