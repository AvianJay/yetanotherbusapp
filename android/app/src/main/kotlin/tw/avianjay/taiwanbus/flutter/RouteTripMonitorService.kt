package tw.avianjay.taiwanbus.flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.drawable.Icon
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.zip.InflaterInputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.json.JSONArray
import org.json.JSONObject
import org.w3c.dom.Element

class RouteTripMonitorService : Service() {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var notificationManager: NotificationManagerCompat

    private var session: TrackingSession? = null
    private var appInForeground = true
    private var foregroundStarted = false
    private var latestLocation: Location? = null
    private var destinationAlertStage = 0

    private val pollingRunnable = object : Runnable {
        override fun run() {
            if (!foregroundStarted) {
                return
            }
            refreshNotification()
            mainHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(locationResult: LocationResult) {
            latestLocation = locationResult.lastLocation
            refreshNotification()
        }
    }

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        notificationManager = NotificationManagerCompat.from(this)
        createNotificationChannels()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTracking()
                return START_NOT_STICKY
            }

            ACTION_SET_APP_FOREGROUND -> {
                appInForeground = intent.getBooleanExtra(EXTRA_APP_IN_FOREGROUND, true)
                refreshNotification()
                return START_STICKY
            }

            ACTION_START_OR_UPDATE -> {
                val sessionJson = intent.getStringExtra(EXTRA_SESSION_JSON)
                val parsedSession = sessionJson?.let(::parseSession)
                if (parsedSession == null) {
                    stopTracking()
                    return START_NOT_STICKY
                }

                val previousDestination = session?.destinationStopId
                session = parsedSession
                appInForeground = parsedSession.appInForeground
                if (previousDestination != parsedSession.destinationStopId) {
                    destinationAlertStage = 0
                }
                latestLocation = parsedSession.initialLatitude?.let { latitude ->
                    parsedSession.initialLongitude?.let { longitude ->
                        Location("trip_monitor_session").apply {
                            this.latitude = latitude
                            this.longitude = longitude
                        }
                    }
                } ?: latestLocation

                ensureForegroundStarted(parsedSession)
                requestLocationUpdates()
                refreshNotification()
                startPolling()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        runCatching {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun ensureForegroundStarted(session: TrackingSession) {
        if (foregroundStarted) {
            return
        }

        val initialNotification = buildTrackingNotification(
            TrackingSnapshot(
                title = session.routeName,
                content = if (appInForeground) {
                    "準備背景乘車提醒..."
                } else {
                    "背景乘車提醒已啟動"
                },
                subText = session.pathName.ifBlank { "即使切到背景也會持續更新" },
                progressMax = null,
                progressValue = null,
                shortCriticalText = "啟動中",
            ),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                TRACKING_NOTIFICATION_ID,
                initialNotification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(TRACKING_NOTIFICATION_ID, initialNotification)
        }
        foregroundStarted = true
    }

    private fun requestLocationUpdates() {
        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            LOCATION_UPDATE_INTERVAL_MS,
        ).setMinUpdateDistanceMeters(20f)
            .setMinUpdateIntervalMillis(LOCATION_MIN_UPDATE_INTERVAL_MS)
            .build()

        runCatching {
            fusedLocationClient.requestLocationUpdates(
                request,
                locationCallback,
                Looper.getMainLooper(),
            )
        }
        runCatching {
            fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                if (location != null) {
                    latestLocation = location
                    refreshNotification()
                }
            }
        }
    }

    private fun startPolling() {
        mainHandler.removeCallbacks(pollingRunnable)
        mainHandler.post(pollingRunnable)
    }

    private fun refreshNotification() {
        val currentSession = session ?: return
        ioExecutor.execute {
            val trackingSnapshot = buildSnapshot(currentSession, latestLocation)
            val notification = buildTrackingNotification(trackingSnapshot)
            notificationManager.notify(TRACKING_NOTIFICATION_ID, notification)
            maybeSendDestinationAlert(currentSession, trackingSnapshot)
        }
    }

    private fun buildSnapshot(
        session: TrackingSession,
        location: Location?,
    ): TrackingSnapshot {
        val liveStops = fetchLiveStopMap(session.routeKey)
        if (location == null) {
            return TrackingSnapshot(
                title = session.routeName,
                content = "等待目前位置...",
                subText = session.pathName.ifBlank { "背景乘車提醒進行中" },
                progressMax = null,
                progressValue = null,
                shortCriticalText = "定位中",
            )
        }

        val nearestIndex = session.stops
            .indices
            .minByOrNull { index ->
                val stop = session.stops[index]
                distanceMeters(
                    location.latitude,
                    location.longitude,
                    stop.lat,
                    stop.lon,
                )
            } ?: -1
        if (nearestIndex == -1) {
            return TrackingSnapshot(
                title = session.routeName,
                content = "暫時無法判斷最近站牌",
                subText = session.pathName.ifBlank { "背景乘車提醒進行中" },
                progressMax = null,
                progressValue = null,
                shortCriticalText = "更新中",
            )
        }

        val nearestStop = session.stops[nearestIndex]
        val nearestLiveStop = liveStops[nearestStop.stopId]
        val busIndex = findClosestBusIndex(session.stops, liveStops, nearestIndex)
        val busStopsAway = busIndex?.let { (nearestIndex - it).coerceAtLeast(0) }
        val nearestEtaText = formatEtaText(nearestLiveStop)
        val nearestEtaShort = formatShortEtaText(nearestLiveStop)
        val nearestSubText = buildNearestSubText(
            session = session,
            nearestStop = nearestStop,
            busStopsAway = busStopsAway,
            nearestEtaText = nearestEtaText,
        )

        val destinationIndex = session.destinationStopId?.let { destinationStopId ->
            session.stops.indexOfFirst { stop -> stop.stopId == destinationStopId }
                .takeIf { it >= 0 }
        }
        if (destinationIndex == null) {
            return TrackingSnapshot(
                title = session.routeName,
                content = "${nearestStop.stopName} · $nearestEtaText",
                subText = nearestSubText,
                progressMax = null,
                progressValue = null,
                shortCriticalText = buildShortCriticalText(busStopsAway, nearestEtaShort),
            )
        }

        val destinationStop = session.stops[destinationIndex]
        val destinationLive = liveStops[destinationStop.stopId]
        val remainingStops = (destinationIndex - nearestIndex).coerceAtLeast(0)
        val destinationEtaText = formatEtaText(destinationLive)
        val destinationEtaShort = formatShortEtaText(destinationLive)
        val destinationDistanceMeters = distanceMeters(
            location.latitude,
            location.longitude,
            destinationStop.lat,
            destinationStop.lon,
        )
        val currentProgress = (nearestIndex + 1).coerceAtMost(destinationIndex + 1)

        return TrackingSnapshot(
            title = "${session.routeName} · ${destinationStop.stopName}",
            content = when {
                remainingStops == 0 -> "已接近 ${destinationStop.stopName}"
                else -> "${destinationStop.stopName} 還有 $remainingStops 站 · $destinationEtaText"
            },
            subText = "最近站牌 ${nearestStop.stopName} · $nearestEtaText",
            progressMax = destinationIndex + 1,
            progressValue = currentProgress,
            destinationName = destinationStop.stopName,
            remainingStops = remainingStops,
            destinationDistanceMeters = destinationDistanceMeters,
            shortCriticalText = buildShortCriticalText(remainingStops, destinationEtaShort),
        )
    }

    private fun buildNearestSubText(
        session: TrackingSession,
        nearestStop: TrackingStop,
        busStopsAway: Int?,
        nearestEtaText: String,
    ): String {
        val parts = mutableListOf<String>()
        if (session.pathName.isNotBlank()) {
            parts += session.pathName
        }
        parts += "最近站牌 ${nearestStop.stopName}"
        if (nearestEtaText != "--") {
            parts += nearestEtaText
        }
        buildBusDistanceText(busStopsAway)?.let(parts::add)
        return parts.joinToString(" · ")
    }

    private fun buildTrackingNotification(snapshot: TrackingSnapshot): Notification {
        val currentSession = session ?: return buildStoppedNotification()
        return if (supportsFrameworkLiveUpdate()) {
            buildFrameworkTrackingNotification(currentSession, snapshot)
        } else {
            buildCompatTrackingNotification(currentSession, snapshot)
        }
    }

    private fun buildStoppedNotification(): Notification {
        return NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle("YABus")
            .setContentText("背景乘車提醒已停止")
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun buildCompatTrackingNotification(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): Notification {
        val builder = NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setContentIntent(createOpenRoutePendingIntent(session))
            .setDeleteIntent(createStopPendingIntent())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPublicVersion(buildPublicTrackingNotification(snapshot))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setColorized(true)
            .setColor(ACCENT_COLOR)
            .addAction(
                NotificationCompat.Action.Builder(
                    0,
                    "停止",
                    createStopPendingIntent(),
                ).build(),
            )

        builder.setShortCriticalText(snapshot.shortCriticalText ?: "更新中")

        requestPromotedOngoing(builder)
        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null) {
            builder.setProgress(progressMax, progressValue, false)
            val progressStyle = NotificationCompat.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(progressValue)
                .setProgressTrackerIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_notification_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Point(progressMax),
                    ),
                )
                .setProgressEndIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_progress_flag),
                )
            builder.setStyle(progressStyle)
        } else {
            builder.setProgress(0, 0, false)
        }

        return builder.build()
    }

    private fun buildFrameworkTrackingNotification(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): Notification {
        val builder = Notification.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setContentIntent(createOpenRoutePendingIntent(session))
            .setDeleteIntent(createStopPendingIntent())
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPublicVersion(buildPublicTrackingNotification(snapshot))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setColorized(true)
            .setColor(ACCENT_COLOR)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "停止",
                    createStopPendingIntent(),
                ).build(),
            )

        builder.setShortCriticalText(snapshot.shortCriticalText ?: "更新中")

        requestPromotedOngoing(builder)
        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null) {
            builder.setProgress(progressMax, progressValue, false)
            val progressStyle = Notification.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(progressValue)
                .setProgressTrackerIcon(
                    Icon.createWithResource(this, R.drawable.ic_notification_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        Notification.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    mutableListOf(
                        Notification.ProgressStyle.Point(progressMax),
                    ),
                )
                .setProgressEndIcon(
                    Icon.createWithResource(this, R.drawable.ic_progress_flag),
                )
            builder.setStyle(progressStyle)
        }

        return builder.build()
    }

    private fun buildPublicTrackingNotification(snapshot: TrackingSnapshot): Notification {
        return NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun buildLegacyTrackingNotification(snapshot: TrackingSnapshot): android.app.Notification {
        val currentSession = session ?: return NotificationCompat.Builder(
            this,
            TRACKING_CHANNEL_ID,
        ).setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle("YABus")
            .setContentText("背景乘車提醒已停止")
            .build()

        val builder = NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setContentIntent(createOpenRoutePendingIntent(currentSession))
            .setDeleteIntent(createStopPendingIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setRequestPromotedOngoing(true)
            .addAction(
                NotificationCompat.Action.Builder(
                    0,
                    "停止",
                    createStopPendingIntent(),
                ).build(),
            )

        if (snapshot.subText.isNotBlank()) {
            builder.setSubText(snapshot.subText)
        }
        snapshot.shortCriticalText?.let(builder::setShortCriticalText)

        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null) {
            builder.setProgress(progressMax, progressValue, false)
            val progressStyle = NotificationCompat.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(progressValue)
                .setProgressTrackerIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_notification_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Point(progressMax),
                    ),
                )
                .setProgressEndIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_progress_flag),
                )
            builder.setStyle(progressStyle)
        } else {
            builder.setProgress(0, 0, false)
        }

        return builder.build()
    }

    private fun maybeSendDestinationAlert(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        if (appInForeground) {
            return
        }
        val destinationName = snapshot.destinationName ?: return
        val remainingStops = snapshot.remainingStops ?: return
        val distanceMeters = snapshot.destinationDistanceMeters ?: return

        if (remainingStops <= 2 && destinationAlertStage < 1) {
            destinationAlertStage = 1
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification_bus)
                    .setContentTitle("${session.routeName} 快到了")
                    .setContentText("$destinationName 還有 $remainingStops 站")
                    .setSubText(session.pathName)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setPublicVersion(
                        NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                            .setSmallIcon(R.drawable.ic_notification_bus)
                            .setContentTitle("${session.routeName} 快到了")
                            .setContentText("$destinationName 還有 $remainingStops 站")
                            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                            .build(),
                    )
                    .setStyle(
                        NotificationCompat.BigTextStyle().bigText(
                            "$destinationName 大約還有 $remainingStops 站，請留意站序，準備下車。",
                        ),
                    )
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_REMINDER)
                    .setAutoCancel(true)
                    .setContentIntent(createOpenRoutePendingIntent(session))
                    .build(),
            )
        }

        if ((remainingStops == 0 || distanceMeters <= 120.0) && destinationAlertStage < 2) {
            destinationAlertStage = 2
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification_bus)
                    .setContentTitle("準備下車")
                    .setContentText("你已接近 $destinationName")
                    .setSubText(session.pathName)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setPublicVersion(
                        NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                            .setSmallIcon(R.drawable.ic_notification_bus)
                            .setContentTitle("準備下車")
                            .setContentText("你已接近 $destinationName")
                            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                            .build(),
                    )
                    .setStyle(
                        NotificationCompat.BigTextStyle().bigText(
                            "你已接近 $destinationName，請準備下車。",
                        ),
                    )
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_ALARM)
                    .setAutoCancel(true)
                    .setContentIntent(createOpenRoutePendingIntent(session))
                    .build(),
            )
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                TRACKING_CHANNEL_ID,
                "背景乘車提醒",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "在背景持續追蹤目前路線與下車提醒。"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "下車提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "接近目的地時提醒你準備下車。"
                enableLights(true)
                lightColor = Color.CYAN
                enableVibration(true)
            },
        )
    }

    private fun createOpenRoutePendingIntent(session: TrackingSession): PendingIntent {
        val intent = AppLaunchConstants.createRouteDetailIntent(
            context = this,
            provider = session.provider,
            routeKey = session.routeKey,
            pathId = session.pathId,
            stopId = session.destinationStopId ?: session.stops.firstOrNull()?.stopId ?: 0,
        )
        return PendingIntent.getActivity(
            this,
            session.routeKey * 101 + session.pathId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createStopPendingIntent(): PendingIntent {
        val intent = Intent(this, RouteTripMonitorService::class.java).apply {
            action = ACTION_STOP
        }
        return PendingIntent.getService(
            this,
            404,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopTracking() {
        foregroundStarted = false
        session = null
        latestLocation = null
        mainHandler.removeCallbacksAndMessages(null)
        runCatching {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun fetchLiveStopMap(routeKey: Int): Map<Int, LiveStopState> {
        val connection = URL("https://busserver.bus.yahoo.com/api/route/$routeKey")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.doInput = true
        connection.useCaches = false

        return try {
            if (connection.responseCode !in 200..299) {
                return emptyMap()
            }
            val xmlText = decodeZlib(connection.inputStream)
            parseLiveStopMap(xmlText)
        } catch (_: Exception) {
            emptyMap()
        } finally {
            connection.disconnect()
        }
    }

    private fun decodeZlib(inputStream: InputStream): String {
        val bytes = inputStream.readBytes()
        return InflaterInputStream(ByteArrayInputStream(bytes))
            .bufferedReader(Charsets.UTF_8)
            .use { reader ->
                reader.readText()
            }
    }

    private fun parseLiveStopMap(xmlText: String): Map<Int, LiveStopState> {
        val builder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        val document = builder.parse(xmlText.byteInputStream(Charsets.UTF_8))
        val elements = document.getElementsByTagName("e")
        val result = mutableMapOf<Int, LiveStopState>()
        for (index in 0 until elements.length) {
            val element = elements.item(index) as? Element ?: continue
            val stopId = element.getAttribute("id").toIntOrNull() ?: continue
            val vehicleIds = mutableListOf<String>()
            val buses = element.getElementsByTagName("b")
            for (busIndex in 0 until buses.length) {
                val busElement = buses.item(busIndex) as? Element ?: continue
                val vehicleId = busElement.getAttribute("id")
                if (vehicleId.isNotBlank()) {
                    vehicleIds += vehicleId
                }
            }
            result[stopId] = LiveStopState(
                seconds = element.getAttribute("sec").toIntOrNull(),
                message = element.getAttribute("msg").takeIf { it.isNotBlank() },
                vehicleIds = vehicleIds,
            )
        }
        return result
    }

    private fun parseSession(sessionJson: String): TrackingSession? {
        return try {
            val root = JSONObject(sessionJson)
            val stopsJson = root.optJSONArray("stops") ?: JSONArray()
            val stops = mutableListOf<TrackingStop>()
            for (index in 0 until stopsJson.length()) {
                val stop = stopsJson.optJSONObject(index) ?: continue
                stops += TrackingStop(
                    stopId = stop.optInt("stopId", 0),
                    stopName = stop.optString("stopName", ""),
                    sequence = stop.optInt("sequence", index),
                    lat = stop.optDouble("lat", 0.0),
                    lon = stop.optDouble("lon", 0.0),
                )
            }
            if (stops.isEmpty()) {
                return null
            }
            TrackingSession(
                provider = root.optString("provider", "twn"),
                routeKey = root.optInt("routeKey", 0),
                routeName = root.optString("routeName", "YABus"),
                pathId = root.optInt("pathId", 0),
                pathName = root.optString("pathName", ""),
                appInForeground = root.optBoolean("appInForeground", true),
                initialLatitude = root.optDouble("initialLatitude", Double.NaN)
                    .takeUnless { it.isNaN() },
                initialLongitude = root.optDouble("initialLongitude", Double.NaN)
                    .takeUnless { it.isNaN() },
                destinationStopId = root.optInt("destinationStopId", -1)
                    .takeIf { it > 0 },
                destinationStopName = root.optString("destinationStopName", "")
                    .takeIf { it.isNotBlank() },
                stops = stops.sortedBy { stop -> stop.sequence },
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun formatEtaText(liveStopState: LiveStopState?): String {
        liveStopState ?: return "--"
        val message = normalizeEtaMessage(liveStopState.message)
        if (message != null) {
            return message
        }

        val seconds = liveStopState.seconds ?: return "--"
        if (seconds <= 0) {
            return "進站中"
        }
        if (seconds < 60) {
            return "即將進站"
        }
        return "${seconds / 60} 分"
    }

    private fun formatShortEtaText(liveStopState: LiveStopState?): String {
        liveStopState ?: return "--"
        val message = liveStopState.message?.trim().orEmpty()
        if (message.isNotEmpty()) {
            return when {
                message.contains("進站") || message.contains("到站") -> "進站"
                message.contains("即將") -> "即將"
                message.contains("未發車") -> "未發"
                message.contains("末班") -> "末班"
                else -> message.take(6)
            }
        }

        val seconds = liveStopState.seconds ?: return "--"
        if (seconds <= 0) {
            return "進站"
        }
        if (seconds < 60) {
            return "<1分"
        }
        return "${seconds / 60}分"
    }

    private fun normalizeEtaMessage(message: String?): String? {
        val trimmed = message?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return null
        }

        return when {
            trimmed.contains("進站") || trimmed.contains("到站") -> "進站中"
            trimmed.contains("即將") -> "即將進站"
            trimmed.contains("未發車") -> "未發車"
            trimmed.contains("末班") -> "末班已過"
            else -> trimmed
        }
    }

    private fun buildBusDistanceText(busStopsAway: Int?): String? {
        return when (busStopsAway) {
            null -> null
            0 -> "公車就在附近"
            else -> "公車還有 $busStopsAway 站"
        }
    }

    private fun buildShortCriticalText(stopsAway: Int?, etaText: String): String {
        val left = when (stopsAway) {
            null -> null
            0 -> "到站"
            else -> "${stopsAway}站"
        }
        val compact = when {
            left == null && etaText == "--" -> "更新中"
            left == null -> etaText
            etaText == "--" -> left
            else -> "$left|$etaText"
        }
        return compact.take(7)
    }

    private fun buildLegacyShortCriticalText(stopsAway: Int?, etaText: String): String? {
        if (stopsAway == null && etaText == "--") {
            return null
        }

        val left = when (stopsAway) {
            null -> null
            0 -> "到站"
            else -> "${stopsAway}站"
        }
        if (left == null) {
            return etaText
        }
        if (etaText == "--") {
            return left
        }
        return "$left | $etaText"
    }

    private fun findClosestBusIndex(
        stops: List<TrackingStop>,
        liveStops: Map<Int, LiveStopState>,
        nearestIndex: Int,
    ): Int? {
        val busIndexes = stops.mapIndexedNotNull { index, stop ->
            val liveStop = liveStops[stop.stopId] ?: return@mapIndexedNotNull null
            if (isBusApproachingStop(liveStop)) {
                index
            } else {
                null
            }
        }
        val behindOrAtUser = busIndexes.filter { it <= nearestIndex }
        if (behindOrAtUser.isNotEmpty()) {
            return behindOrAtUser.maxOrNull()
        }
        return busIndexes.minOrNull()
    }

    private fun isBusApproachingStop(liveStop: LiveStopState): Boolean {
        val message = liveStop.message?.trim().orEmpty()
        return liveStop.vehicleIds.isNotEmpty() ||
            (liveStop.seconds != null && liveStop.seconds <= 0) ||
            message.contains("進站") ||
            message.contains("到站")
    }

    private fun distanceMeters(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
    ): Double {
        val results = FloatArray(1)
        Location.distanceBetween(lat1, lon1, lat2, lon2, results)
        return results[0].toDouble()
    }

    private fun requestPromotedOngoing(builder: Notification.Builder) {
        runCatching {
            builder.javaClass.getMethod(
                "setRequestPromotedOngoing",
                Boolean::class.javaPrimitiveType,
            ).invoke(builder, true)
        }
    }

    private fun requestPromotedOngoing(builder: NotificationCompat.Builder) {
        builder.setRequestPromotedOngoing(true)
    }

    private fun supportsFrameworkLiveUpdate(): Boolean {
        return false
    }

    companion object {
        private const val ACTION_START_OR_UPDATE =
            "tw.avianjay.taiwanbus.flutter.action.START_OR_UPDATE_TRIP_MONITOR"
        private const val ACTION_SET_APP_FOREGROUND =
            "tw.avianjay.taiwanbus.flutter.action.SET_TRIP_MONITOR_APP_FOREGROUND"
        private const val ACTION_STOP =
            "tw.avianjay.taiwanbus.flutter.action.STOP_TRIP_MONITOR"

        private const val EXTRA_SESSION_JSON = "session_json"
        private const val EXTRA_APP_IN_FOREGROUND = "app_in_foreground"

        private const val TRACKING_CHANNEL_ID = "trip_monitor_tracking"
        private const val ALERT_CHANNEL_ID = "trip_monitor_alerts"
        private const val TRACKING_NOTIFICATION_ID = 6021
        private const val ALERT_NOTIFICATION_ID = 6022

        private const val POLL_INTERVAL_MS = 15_000L
        private const val LOCATION_UPDATE_INTERVAL_MS = 12_000L
        private const val LOCATION_MIN_UPDATE_INTERVAL_MS = 6_000L
        private const val LIVE_UPDATE_SDK_INT = 36
        private const val ACCENT_COLOR = -16027003

        fun startOrUpdate(context: Context, session: Map<String, Any?>) {
            val sessionJson = JSONObject(session).toString()
            val intent = Intent(context, RouteTripMonitorService::class.java).apply {
                action = ACTION_START_OR_UPDATE
                putExtra(EXTRA_SESSION_JSON, sessionJson)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun setAppInForeground(context: Context, appInForeground: Boolean) {
            val intent = Intent(context, RouteTripMonitorService::class.java).apply {
                action = ACTION_SET_APP_FOREGROUND
                putExtra(EXTRA_APP_IN_FOREGROUND, appInForeground)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, RouteTripMonitorService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

data class TrackingSession(
    val provider: String,
    val routeKey: Int,
    val routeName: String,
    val pathId: Int,
    val pathName: String,
    val appInForeground: Boolean,
    val initialLatitude: Double?,
    val initialLongitude: Double?,
    val destinationStopId: Int?,
    val destinationStopName: String?,
    val stops: List<TrackingStop>,
)

data class TrackingStop(
    val stopId: Int,
    val stopName: String,
    val sequence: Int,
    val lat: Double,
    val lon: Double,
)

data class LiveStopState(
    val seconds: Int?,
    val message: String?,
    val vehicleIds: List<String>,
)

data class TrackingSnapshot(
    val title: String,
    val content: String,
    val subText: String,
    val progressMax: Int?,
    val progressValue: Int?,
    val shortCriticalText: String? = null,
    val destinationName: String? = null,
    val remainingStops: Int? = null,
    val destinationDistanceMeters: Double? = null,
)
