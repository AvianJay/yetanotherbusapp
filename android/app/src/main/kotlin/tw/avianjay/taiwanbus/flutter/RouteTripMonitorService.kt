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
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
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
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

class RouteTripMonitorService : Service() {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var notificationManager: NotificationManagerCompat
    private val refreshLock = Any()

    private var session: TrackingSession? = null
    private var appInForeground = true
    private var foregroundStarted = false
    private var latestLocation: Location? = null
    private var lastMovementLocation: Location? = null
    private var lastMovementNearestIndex: Int? = null
    private var lastMovementRecordedAtMs = 0L
    private var boardingAlertSent = false
    private var boardingCheckPromptSent = false
    private var boardingWindowOpen = false
    private var boardingWindowOpenedAtMs = 0L
    private var boardingCheckSnoozeUntilMs = 0L
    private var rideConfirmed = false
    private var rideConfirmationSamples = 0
    private var lastNearestStopIndex: Int? = null
    private var lastBusStopIndex: Int? = null
    private var activeBoardingVehicleId: String? = null
    private var activeBoardingVehicleStopIndex: Int? = null
    private var activeBoardingVehicleLastSeenAtMs = 0L
    private var activeBoardingVehiclePassedAtMs = 0L
    private var trackedBusId: String? = null
    private var destinationSetupPromptSent = false
    private var arrivalDetectedAtMs = 0L
    private var destinationAlertStage = 0
    private var overshootAlertSent = false
    private var lastWentBackgroundAtMs = 0L
    private var refreshInFlight = false
    private var refreshPending = false
    private var lastRefreshStartedAtMs = 0L
    private var cachedLiveRouteId: String? = null
    private var cachedLivePathId: Int? = null
    private var cachedLiveFetchedAtMs = 0L
    private var cachedLiveStops: Map<Int, LiveStopState> = emptyMap()

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
                AppRuntimeStateStore.clearPausedTripMonitor(this)
                stopTracking()
                return START_NOT_STICKY
            }

            ACTION_PAUSE -> {
                val reason = intent.getStringExtra(EXTRA_PAUSE_REASON)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: PAUSE_REASON_USER
                val explicitSession = intent.getStringExtra(EXTRA_SESSION_JSON)?.let(::parseSessionJson)
                pauseTracking(reason, explicitSession)
                return START_NOT_STICKY
            }

            ACTION_SET_APP_FOREGROUND -> {
                appInForeground = intent.getBooleanExtra(EXTRA_APP_IN_FOREGROUND, true)
                lastWentBackgroundAtMs = if (appInForeground) {
                    0L
                } else {
                    System.currentTimeMillis()
                }
                AppRuntimeStateStore.setAppInForeground(this, appInForeground)
                if (session == null) {
                    return START_NOT_STICKY
                }
                refreshNotification(force = true)
                startPolling()
                return START_STICKY
            }

            ACTION_RESUME -> {
                AppRuntimeStateStore.clearPausedTripMonitor(this)
                return START_NOT_STICKY
            }

            ACTION_MARK_BOARDED -> {
                rideConfirmed = true
                rideConfirmationSamples = REQUIRED_RIDE_CONFIRMATION_SAMPLES
                boardingWindowOpen = true
                boardingCheckPromptSent = true
                trackedBusId = normalizeVehicleId(activeBoardingVehicleId) ?: trackedBusId
                activeBoardingVehiclePassedAtMs = 0L
                notificationManager.cancel(ALERT_NOTIFICATION_ID)
                refreshNotification(force = true)
                return START_STICKY
            }

            ACTION_NOT_BOARDED -> {
                boardingAlertSent = false
                rideConfirmed = false
                rideConfirmationSamples = 0
                boardingCheckPromptSent = false
                boardingWindowOpen = false
                boardingWindowOpenedAtMs = 0L
                trackedBusId = null
                activeBoardingVehicleId = null
                activeBoardingVehicleStopIndex = null
                activeBoardingVehicleLastSeenAtMs = 0L
                activeBoardingVehiclePassedAtMs = 0L
                lastMovementLocation = null
                lastMovementNearestIndex = null
                lastMovementRecordedAtMs = 0L
                boardingCheckSnoozeUntilMs =
                    System.currentTimeMillis() + BOARDING_CHECK_SNOOZE_MS
                notificationManager.cancel(ALERT_NOTIFICATION_ID)
                refreshNotification(force = true)
                return START_STICKY
            }

            ACTION_START_OR_UPDATE -> {
                val sessionJson = intent.getStringExtra(EXTRA_SESSION_JSON)
                val parsedSession = sessionJson?.let(::parseSessionJson)
                if (parsedSession == null) {
                    stopTracking()
                    return START_NOT_STICKY
                }

                val previousDestination = session?.destinationStopId
                val previousBoarding = session?.boardingStopId
                val previousRouteId = session?.routeId
                if (AppRuntimeStateStore.isTripMonitorPausedFor(this, parsedSession)) {
                    session = parsedSession
                    appInForeground = parsedSession.appInForeground
                    stopTracking()
                    return START_NOT_STICKY
                }
                session = parsedSession
                appInForeground = parsedSession.appInForeground
                if (!appInForeground && lastWentBackgroundAtMs == 0L) {
                    lastWentBackgroundAtMs = System.currentTimeMillis()
                }
                AppRuntimeStateStore.setAppInForeground(this, appInForeground)
                if (
                    previousDestination != parsedSession.destinationStopId ||
                    previousBoarding != parsedSession.boardingStopId ||
                    previousRouteId != parsedSession.routeId
                ) {
                    boardingAlertSent = false
                    boardingCheckPromptSent = false
                    boardingWindowOpen = false
                    boardingWindowOpenedAtMs = 0L
                    boardingCheckSnoozeUntilMs = 0L
                    rideConfirmed = false
                    rideConfirmationSamples = 0
                    lastNearestStopIndex = null
                    lastBusStopIndex = null
                    activeBoardingVehicleId = null
                    activeBoardingVehicleStopIndex = null
                    activeBoardingVehicleLastSeenAtMs = 0L
                    activeBoardingVehiclePassedAtMs = 0L
                    lastMovementLocation = null
                    lastMovementNearestIndex = null
                    lastMovementRecordedAtMs = 0L
                    trackedBusId = null
                    destinationSetupPromptSent = false
                    arrivalDetectedAtMs = 0L
                    destinationAlertStage = 0
                    overshootAlertSent = false
                }
                latestLocation = createSessionLocation(parsedSession) ?: latestLocation

                ensureForegroundStarted(parsedSession)
                requestLocationUpdates()
                refreshNotification(force = true)
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

    private fun buildStartupSnapshot(session: TrackingSession): TrackingSnapshot {
        val startupLocation = latestLocation ?: createSessionLocation(session)
        val nearestIndex = startupLocation?.let { location ->
            findNearestStopIndex(session.stops, location)
        } ?: -1
        val subTextParts = mutableListOf<String>()
        if (session.pathName.isNotBlank()) {
            subTextParts += session.pathName
        }
        session.boardingStopName?.takeIf { it.isNotBlank() }?.let { stopName ->
            subTextParts += "上車站 $stopName"
        }
        session.destinationStopName?.takeIf { it.isNotBlank() }?.let { stopName ->
            subTextParts += "下車站 $stopName"
        }
        val content = when {
            nearestIndex >= 0 -> "最近站牌 ${session.stops[nearestIndex].stopName}"
            session.destinationStopName?.isNotBlank() == true ->
                "已啟動 ${session.destinationStopName} 下車提醒"
            session.boardingStopName?.isNotBlank() == true ->
                "已啟動 ${session.boardingStopName} 乘車提醒"
            appInForeground -> "已啟動這條路線的乘車提醒"
            else -> "背景乘車提醒已啟動"
        }
        return TrackingSnapshot(
            title = session.routeName,
            content = content,
            subText = subTextParts.ifEmpty { listOf("背景乘車提醒已啟動") }.joinToString(" · "),
            progressMax = null,
            progressValue = null,
            shortCriticalText = null,
        )
    }

    private fun createSessionLocation(session: TrackingSession): Location? {
        return session.initialLatitude?.let { latitude ->
            session.initialLongitude?.let { longitude ->
                Location("trip_monitor_session").apply {
                    this.latitude = latitude
                    this.longitude = longitude
                }
            }
        }
    }

    private fun ensureForegroundStarted(session: TrackingSession) {
        val initialNotification = buildTrackingNotification(buildStartupSnapshot(session))
        if (foregroundStarted) {
            notificationManager.notify(TRACKING_NOTIFICATION_ID, initialNotification)
            return
        }
        startForegroundInternal(initialNotification)
    }

    private fun startForegroundInternal(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                TRACKING_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(TRACKING_NOTIFICATION_ID, notification)
        }
        foregroundStarted = true
    }

    private fun requestLocationUpdates() {
        if (session?.backgroundLocationAlwaysGranted != true) {
            return
        }
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
        if (!foregroundStarted) {
            return
        }
        mainHandler.postDelayed(pollingRunnable, POLL_INTERVAL_MS)
    }

    private fun stopPolling() {
        mainHandler.removeCallbacks(pollingRunnable)
    }

    private fun refreshNotification(force: Boolean = false) {
        val currentSession = session ?: return
        synchronized(refreshLock) {
            val now = SystemClock.elapsedRealtime()
            if (refreshInFlight) {
                refreshPending = true
                return
            }
            if (
                !force &&
                lastRefreshStartedAtMs != 0L &&
                now - lastRefreshStartedAtMs < MIN_REFRESH_INTERVAL_MS
            ) {
                return
            }
            refreshInFlight = true
            lastRefreshStartedAtMs = now
        }
        ioExecutor.execute {
            try {
                val trackingSnapshot = buildSnapshot(currentSession, latestLocation)
                val notification = buildTrackingNotification(trackingSnapshot)
                notificationManager.notify(TRACKING_NOTIFICATION_ID, notification)
                maybeSendTripAlerts(currentSession, trackingSnapshot)
            } finally {
                var shouldRefreshAgain = false
                synchronized(refreshLock) {
                    refreshInFlight = false
                    if (refreshPending) {
                        refreshPending = false
                        shouldRefreshAgain = true
                    } else {
                        refreshPending = false
                    }
                }
                if (shouldRefreshAgain) {
                    mainHandler.postDelayed(
                        { refreshNotification() },
                        MIN_REFRESH_INTERVAL_MS,
                    )
                }
            }
        }
    }

    private fun buildSnapshot(
        session: TrackingSession,
        location: Location?,
    ): TrackingSnapshot {
        val liveStops = fetchLiveStopMap(session)
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

        val nearestIndex = findNearestStopIndex(session.stops, location)
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
        val nearestStopDistanceMeters = distanceMeters(
            location.latitude,
            location.longitude,
            nearestStop.lat,
            nearestStop.lon,
        )
        val nearestLiveStop = liveStops[nearestStop.stopId]
        val nearestEtaText = displayEtaText(nearestLiveStop)
        val busIndex = findClosestBusIndex(session.stops, liveStops, nearestIndex)
        val destinationIndex = session.destinationStopId?.let { destinationStopId ->
            session.stops.indexOfFirst { stop -> stop.stopId == destinationStopId }
                .takeIf { it >= 0 }
        }

        if (destinationIndex == null && session.boardingStopId != null) {
            val boardingIndex = session.stops.indexOfFirst { stop ->
                stop.stopId == session.boardingStopId
            }.takeIf { it >= 0 } ?: nearestIndex
            val boardingStop = session.stops[boardingIndex]
            val boardingLiveStop = liveStops[boardingStop.stopId]
            val boardingVehicleCandidate = resolveBoardingVehicleCandidate(
                stops = session.stops,
                liveStops = liveStops,
                location = location,
                nearestIndex = nearestIndex,
                boardingIndex = boardingIndex,
            )
            val boardingVehicleId = boardingVehicleCandidate?.vehicleId ?: activeBoardingVehicleId
            val boardingEtaText = displayEtaText(boardingLiveStop, boardingVehicleId)
            val boardingEtaSeconds = resolveEtaSeconds(boardingLiveStop, boardingVehicleId)
            val boardingDistanceMeters = distanceMeters(
                location.latitude,
                location.longitude,
                boardingStop.lat,
                boardingStop.lon,
            )
            val fallbackBoardingBusIndex = findClosestBusIndexForBoarding(
                stops = session.stops,
                liveStops = liveStops,
                boardingIndex = boardingIndex,
            )
            val boardingBusIndex =
                boardingVehicleCandidate?.stopIndex ?: activeBoardingVehicleStopIndex ?: fallbackBoardingBusIndex
            val busStopsUntilBoarding = boardingBusIndex?.let {
                (boardingIndex - it).coerceAtLeast(0)
            }
            val rideState = if (session.backgroundLocationAlwaysGranted) {
                updateRideState(
                    location = location,
                    nearestIndex = nearestIndex,
                    boardingIndex = boardingIndex,
                    boardingBusIndex = boardingBusIndex,
                    boardingVehicleId = boardingVehicleId,
                    boardingEtaText = boardingEtaText,
                    boardingEtaSeconds = boardingEtaSeconds,
                    boardingDistanceMeters = boardingDistanceMeters,
                )
            } else {
                RideStateUpdate(
                    hasBoarded = hasBusReachedBoardingStop(
                        busStopsUntilBoarding = busStopsUntilBoarding,
                        boardingEtaText = boardingEtaText,
                        boardingEtaSeconds = boardingEtaSeconds,
                    ),
                )
            }
            val userBusLiveStop = busIndex?.let { liveStops[session.stops[it].stopId] }
            trackedBusId = if (rideState.hasBoarded) {
                normalizeVehicleId(boardingVehicleId) ?: selectTrackedBusId(
                    currentTrackedBusId = trackedBusId ?: boardingVehicleId,
                    nearestLiveStop = nearestLiveStop,
                    boardingLiveStop = boardingLiveStop,
                    destinationLiveStop = null,
                    userBusLiveStop = userBusLiveStop,
                )
            } else {
                null
            }
            val busStopsAway = busIndex?.let { (nearestIndex - it).coerceAtLeast(0) }
            val boardingProgressValue = if (rideState.hasBoarded) {
                val trackedPos = boardingBusIndex ?: nearestIndex
                (trackedPos + 1).coerceIn(1, boardingIndex + 1)
            } else {
                boardingBusIndex?.plus(1)?.coerceAtMost(boardingIndex + 1) ?: 0
            }
            return TrackingSnapshot(
                title = session.routeName,
                content = "${nearestStop.stopName} 約 $nearestEtaText",
                subText = buildNearestStatusText(
                    session = session,
                    nearestStop = nearestStop,
                    nearestEtaText = nearestEtaText,
                    busStopsAway = busStopsAway,
                ),
                progressMax = boardingIndex + 1,
                progressValue = boardingProgressValue,
                shortCriticalText = buildShortCriticalText(
                    busStopsAway,
                    displayShortEtaText(nearestLiveStop),
                ),
                hasBoarded = rideState.hasBoarded,
                boardingName = boardingStop.stopName,
                boardingEtaText = boardingEtaText,
                boardingEtaSeconds = boardingEtaSeconds,
                boardingStopsAway = busStopsUntilBoarding,
                boardingDistanceMeters = boardingDistanceMeters,
                boardingVehicleId = boardingVehicleId,
                boardingVehiclePassedStop = rideState.boardingVehiclePassedStop,
                boardingPromptEligible = rideState.boardingPromptEligible,
                nearestStopDistanceMeters = nearestStopDistanceMeters,
            )
        }

        if (destinationIndex == null) {
            trackedBusId = null
            val busStopsAway = busIndex?.let { (nearestIndex - it).coerceAtLeast(0) }
            return TrackingSnapshot(
                title = session.routeName,
                content = "${nearestStop.stopName} · $nearestEtaText",
                subText = buildNearestStatusText(
                    session = session,
                    nearestStop = nearestStop,
                    nearestEtaText = nearestEtaText,
                    busStopsAway = busStopsAway,
                ),
                progressMax = null,
                progressValue = null,
                shortCriticalText = buildShortCriticalText(
                    busStopsAway,
                    displayShortEtaText(nearestLiveStop),
                ),
            )
        }

        val destinationStop = session.stops[destinationIndex]
        val boardingIndex = resolveBoardingIndex(session, nearestIndex, destinationIndex)
        val boardingStop = session.stops[boardingIndex]
        val boardingLiveStop = liveStops[boardingStop.stopId]
        val boardingVehicleCandidate = resolveBoardingVehicleCandidate(
            stops = session.stops,
            liveStops = liveStops,
            location = location,
            nearestIndex = nearestIndex,
            boardingIndex = boardingIndex,
        )
        val boardingVehicleId = boardingVehicleCandidate?.vehicleId ?: activeBoardingVehicleId
        val boardingEtaText = displayEtaText(boardingLiveStop, boardingVehicleId)
        val boardingEtaShort = displayShortEtaText(boardingLiveStop, boardingVehicleId)
        val boardingEtaSeconds = resolveEtaSeconds(boardingLiveStop, boardingVehicleId)
        val boardingDistanceMeters = distanceMeters(
            location.latitude,
            location.longitude,
            boardingStop.lat,
            boardingStop.lon,
        )
        val fallbackBoardingBusIndex = findClosestBusIndexForBoarding(
            stops = session.stops,
            liveStops = liveStops,
            boardingIndex = boardingIndex,
        )
        val boardingBusIndex =
            boardingVehicleCandidate?.stopIndex ?: activeBoardingVehicleStopIndex ?: fallbackBoardingBusIndex
        val busStopsUntilBoarding = boardingBusIndex?.let {
            (boardingIndex - it).coerceAtLeast(0)
        }
        val rideState = if (session.backgroundLocationAlwaysGranted) {
            updateRideState(
                location = location,
                nearestIndex = nearestIndex,
                boardingIndex = boardingIndex,
                boardingBusIndex = boardingBusIndex,
                boardingVehicleId = boardingVehicleId,
                boardingEtaText = boardingEtaText,
                boardingEtaSeconds = boardingEtaSeconds,
                boardingDistanceMeters = boardingDistanceMeters,
            )
        } else {
            RideStateUpdate(
                hasBoarded = hasBusReachedBoardingStop(
                    busStopsUntilBoarding = busStopsUntilBoarding,
                    boardingEtaText = boardingEtaText,
                    boardingEtaSeconds = boardingEtaSeconds,
                ),
            )
        }

        if (!rideState.hasBoarded) {
            trackedBusId = null
            val boardingProgressValue =
                boardingBusIndex?.plus(1)?.coerceAtMost(boardingIndex + 1) ?: 0
            return TrackingSnapshot(
                title = "${session.routeName} · ${boardingStop.stopName}",
                content = "公車到 ${boardingStop.stopName} 約 $boardingEtaText",
                subText = buildWaitingBoardingText(
                    session = session,
                    boardingStop = boardingStop,
                    destinationStop = destinationStop,
                    busStopsUntilBoarding = busStopsUntilBoarding,
                ),
                progressMax = boardingIndex + 1,
                progressValue = boardingProgressValue,
                shortCriticalText = buildShortCriticalText(
                    busStopsUntilBoarding,
                    boardingEtaShort,
                ),
                boardingName = boardingStop.stopName,
                boardingEtaText = boardingEtaText,
                boardingEtaSeconds = boardingEtaSeconds,
                boardingStopsAway = busStopsUntilBoarding,
                boardingDistanceMeters = boardingDistanceMeters,
                hasBoarded = false,
                boardingVehicleId = boardingVehicleId,
                boardingVehiclePassedStop = rideState.boardingVehiclePassedStop,
                boardingPromptEligible = rideState.boardingPromptEligible,
                destinationName = destinationStop.stopName,
                nearestStopDistanceMeters = nearestStopDistanceMeters,
            )
        }

        val destinationLive = liveStops[destinationStop.stopId]
        val trackedBusIndex =
            findTrackedBusIndex(
                stops = session.stops,
                liveStops = liveStops,
                preferredVehicleId = trackedBusId,
            ) ?: busIndex
        val travelIndex = trackedBusIndex ?: nearestIndex
        val currentStop = session.stops[travelIndex]
        val currentLiveStop = liveStops[currentStop.stopId]
        val rawRemainingStops = destinationIndex - travelIndex
        val remainingStops = rawRemainingStops.coerceAtLeast(0)
        val userBusLiveStop = busIndex?.let { liveStops[session.stops[it].stopId] }
        trackedBusId = selectTrackedBusId(
            currentTrackedBusId = trackedBusId ?: boardingVehicleId,
            nearestLiveStop = nearestLiveStop,
            boardingLiveStop = boardingLiveStop,
            destinationLiveStop = destinationLive,
            userBusLiveStop = userBusLiveStop,
        )
        val destinationEtaText = displayEtaText(destinationLive, trackedBusId)
        val destinationEtaShort = displayShortEtaText(destinationLive, trackedBusId)
        val currentEtaText = displayEtaText(currentLiveStop, trackedBusId)
        val destinationDistanceMeters = distanceMeters(
            location.latitude,
            location.longitude,
            destinationStop.lat,
            destinationStop.lon,
        )
        val journeyStartIndex = boardingIndex.coerceAtMost(destinationIndex)
        val journeyProgressMax = (destinationIndex - journeyStartIndex + 1).coerceAtLeast(1)
        val currentProgress =
            ((travelIndex.coerceAtLeast(journeyStartIndex) - journeyStartIndex) + 1)
                .coerceIn(1, journeyProgressMax)

        return TrackingSnapshot(
            title = "${session.routeName} · ${destinationStop.stopName}",
            content = when {
                remainingStops == 0 -> "已接近 ${destinationStop.stopName}"
                else -> "距離 ${destinationStop.stopName} 還有 $remainingStops 站 · $destinationEtaText"
            },
            subText = "已上車 · 最近站牌 ${nearestStop.stopName} · $nearestEtaText",
            progressMax = journeyProgressMax,
            progressValue = currentProgress,
            shortCriticalText = buildShortCriticalText(
                remainingStops,
                destinationEtaShort,
            ),
            hasBoarded = true,
            destinationName = destinationStop.stopName,
            remainingStops = remainingStops,
            destinationDistanceMeters = destinationDistanceMeters,
            boardingName = boardingStop.stopName,
            boardingVehicleId = trackedBusId ?: boardingVehicleId,
            passedDestinationByStops = (-rawRemainingStops).takeIf { it > 0 },
            nearestStopDistanceMeters = nearestStopDistanceMeters,
        )
    }

    private fun buildSnapshotLegacy(
        session: TrackingSession,
        location: Location?,
    ): TrackingSnapshot {
        val liveStops = fetchLiveStopMap(session)
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
        val currentProgress = (busIndex ?: nearestIndex).plus(1).coerceAtMost(destinationIndex + 1)

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

    private fun resolveBoardingIndex(
        session: TrackingSession,
        nearestIndex: Int,
        destinationIndex: Int,
    ): Int {
        val explicitBoardingIndex = session.boardingStopId?.let { boardingStopId ->
            session.stops.indexOfFirst { stop -> stop.stopId == boardingStopId }
                .takeIf { it >= 0 }
        }
        return (explicitBoardingIndex ?: nearestIndex).coerceAtMost(destinationIndex)
    }

    private fun findNearestStopIndex(
        stops: List<TrackingStop>,
        location: Location,
    ): Int {
        return stops.indices.minByOrNull { index ->
            val stop = stops[index]
            distanceMeters(
                location.latitude,
                location.longitude,
                stop.lat,
                stop.lon,
            )
        } ?: -1
    }

    private fun findClosestStopIndices(
        stops: List<TrackingStop>,
        location: Location,
        count: Int,
    ): List<Int> {
        if (count <= 0) {
            return emptyList()
        }
        return stops.indices
            .sortedBy { index ->
                val stop = stops[index]
                distanceMeters(
                    location.latitude,
                    location.longitude,
                    stop.lat,
                    stop.lon,
                )
            }
            .take(count)
    }

    private fun resolveBoardingVehicleCandidate(
        stops: List<TrackingStop>,
        liveStops: Map<Int, LiveStopState>,
        location: Location,
        nearestIndex: Int,
        boardingIndex: Int,
    ): VehicleCandidate? {
        val now = System.currentTimeMillis()
        val nearbyVehicleIds = linkedSetOf<String>()
        findClosestStopIndices(stops, location, USER_NEARBY_STOP_COUNT).forEach { index ->
            nearbyVehicleIds += extractNormalizedVehicleIds(liveStops[stops[index].stopId])
        }
        normalizeVehicleId(activeBoardingVehicleId)
            ?.takeIf {
                activeBoardingVehicleLastSeenAtMs != 0L &&
                    now - activeBoardingVehicleLastSeenAtMs < ACTIVE_BOARDING_VEHICLE_STALE_MS
            }
            ?.let(nearbyVehicleIds::add)

        val candidates = nearbyVehicleIds.mapNotNull { vehicleId ->
            buildVehicleCandidate(
                stops = stops,
                liveStops = liveStops,
                location = location,
                vehicleId = vehicleId,
            )
        }
        val normalizedActiveVehicleId = normalizeVehicleId(activeBoardingVehicleId)
        val selectedCandidate =
            candidates.firstOrNull { it.vehicleId == normalizedActiveVehicleId }
                ?: candidates.minWithOrNull(
                    compareBy<VehicleCandidate> { if (it.stopIndex > boardingIndex) 1 else 0 }
                        .thenBy {
                            if (it.stopIndex <= boardingIndex) {
                                boardingIndex - it.stopIndex
                            } else {
                                it.stopIndex - boardingIndex
                            }
                        }
                        .thenBy { abs(it.stopIndex - nearestIndex) }
                        .thenBy { it.distanceMeters }
                        .thenBy { it.etaSeconds ?: Int.MAX_VALUE },
                )

        if (selectedCandidate == null) {
            if (
                activeBoardingVehicleLastSeenAtMs != 0L &&
                now - activeBoardingVehicleLastSeenAtMs >= ACTIVE_BOARDING_VEHICLE_STALE_MS
            ) {
                activeBoardingVehicleId = null
                activeBoardingVehicleStopIndex = null
                activeBoardingVehicleLastSeenAtMs = 0L
                activeBoardingVehiclePassedAtMs = 0L
            }
            return null
        }

        val nextVehicleId = selectedCandidate.vehicleId
        val currentVehicleId = normalizeVehicleId(activeBoardingVehicleId)
        if (currentVehicleId != null && currentVehicleId != nextVehicleId && !rideConfirmed) {
            boardingAlertSent = false
            boardingCheckPromptSent = false
            boardingWindowOpen = false
            boardingWindowOpenedAtMs = 0L
            activeBoardingVehiclePassedAtMs = 0L
            rideConfirmationSamples = 0
        }
        activeBoardingVehicleId = nextVehicleId
        activeBoardingVehicleStopIndex = selectedCandidate.stopIndex
        activeBoardingVehicleLastSeenAtMs = now
        return selectedCandidate
    }

    private fun buildVehicleCandidate(
        stops: List<TrackingStop>,
        liveStops: Map<Int, LiveStopState>,
        location: Location,
        vehicleId: String,
    ): VehicleCandidate? {
        val normalizedVehicleId = normalizeVehicleId(vehicleId) ?: return null
        val stopIndex = findTrackedBusIndex(
            stops = stops,
            liveStops = liveStops,
            preferredVehicleId = normalizedVehicleId,
        ) ?: return null
        val stop = stops[stopIndex]
        val stopState = liveStops[stop.stopId]
        return VehicleCandidate(
            vehicleId = normalizedVehicleId,
            stopIndex = stopIndex,
            distanceMeters = distanceMeters(
                location.latitude,
                location.longitude,
                stop.lat,
                stop.lon,
            ),
            etaSeconds = resolveEtaSeconds(stopState, normalizedVehicleId),
        )
    }

    private fun extractNormalizedVehicleIds(stopState: LiveStopState?): Set<String> {
        val result = linkedSetOf<String>()
        stopState?.etaEntries?.forEach { etaEntry ->
            normalizeVehicleId(etaEntry.vehicleId)?.let(result::add)
        }
        stopState?.vehicleIds?.forEach { vehicleId ->
            normalizeVehicleId(vehicleId)?.let(result::add)
        }
        return result
    }

    private fun updateRideState(
        location: Location,
        nearestIndex: Int,
        boardingIndex: Int,
        boardingBusIndex: Int?,
        boardingVehicleId: String?,
        boardingEtaText: String,
        boardingEtaSeconds: Int?,
        boardingDistanceMeters: Double,
    ): RideStateUpdate {
        val userNearBoardingStop =
            boardingDistanceMeters <= BOARDING_STOP_RADIUS_METERS || nearestIndex == boardingIndex
        val busNearBoardingStop =
            (
                boardingBusIndex != null &&
                    boardingBusIndex <= boardingIndex &&
                    boardingIndex - boardingBusIndex <= 1 &&
                    isLikelyBoardingArrival(
                        etaSeconds = boardingEtaSeconds,
                        etaText = boardingEtaText,
                    )
                ) ||
                isImmediateEtaText(boardingEtaText)
        if (userNearBoardingStop && busNearBoardingStop) {
            if (!boardingWindowOpen) {
                boardingWindowOpenedAtMs = System.currentTimeMillis()
            }
            boardingWindowOpen = true
        }

        val movement = updateUserMovement(location, nearestIndex)
        val previousNearest = lastNearestStopIndex
        val previousBusIndex = lastBusStopIndex
        lastNearestStopIndex = nearestIndex
        lastBusStopIndex = boardingBusIndex
        val movedForward = previousNearest != null && nearestIndex > previousNearest
        val busMovedForward =
            previousBusIndex != null &&
                boardingBusIndex != null &&
                boardingBusIndex > previousBusIndex
        val busNearUser = boardingBusIndex != null && abs(nearestIndex - boardingBusIndex) <= 1
        val vehiclePassedBoarding =
            normalizeVehicleId(boardingVehicleId) != null &&
                boardingBusIndex != null &&
                boardingBusIndex > boardingIndex
        if (vehiclePassedBoarding) {
            if (activeBoardingVehiclePassedAtMs == 0L) {
                activeBoardingVehiclePassedAtMs = System.currentTimeMillis()
            }
        } else if (boardingBusIndex != null && boardingBusIndex <= boardingIndex) {
            activeBoardingVehiclePassedAtMs = 0L
        }
        val userReachedBoarding = nearestIndex >= boardingIndex
        val userAdvancedPastBoardingStop = nearestIndex > boardingIndex
        val userMovingWithBus =
            movement.isTransitLike &&
                (busNearUser || vehiclePassedBoarding) &&
                (movedForward || movement.routeIndexDelta > 0 || boardingDistanceMeters > BOARDING_CONFIRM_DISTANCE_METERS)
        val strongBoardingSignal =
            boardingWindowOpen &&
                userReachedBoarding &&
                vehiclePassedBoarding &&
                (
                    userMovingWithBus ||
                        (
                            busMovedForward &&
                                userAdvancedPastBoardingStop &&
                                boardingDistanceMeters <= BOARDING_CONFIRM_DISTANCE_METERS
                        )
                )

        if (!rideConfirmed) {
            rideConfirmationSamples = if (strongBoardingSignal) {
                rideConfirmationSamples + 1
            } else {
                0
            }
            if (rideConfirmationSamples >= REQUIRED_RIDE_CONFIRMATION_SAMPLES) {
                rideConfirmed = true
                boardingCheckPromptSent = true
                trackedBusId = normalizeVehicleId(boardingVehicleId) ?: trackedBusId
            }
        }

        val boardingPromptEligible =
            !rideConfirmed &&
                boardingWindowOpen &&
                vehiclePassedBoarding &&
                !movement.isTransitLike &&
                activeBoardingVehiclePassedAtMs != 0L &&
                System.currentTimeMillis() - activeBoardingVehiclePassedAtMs >=
                    BOARDING_CHECK_AFTER_PASS_DELAY_MS

        return RideStateUpdate(
            hasBoarded = rideConfirmed,
            boardingVehiclePassedStop = vehiclePassedBoarding,
            boardingPromptEligible = boardingPromptEligible,
        )
    }

    private fun updateUserMovement(
        location: Location,
        nearestIndex: Int,
    ): UserMovementState {
        val now = SystemClock.elapsedRealtime()
        val previousLocation = lastMovementLocation
        val previousNearestIndex = lastMovementNearestIndex
        val previousRecordedAtMs = lastMovementRecordedAtMs
        val distanceMovedMeters = if (previousLocation == null) {
            0.0
        } else {
            distanceMeters(
                previousLocation.latitude,
                previousLocation.longitude,
                location.latitude,
                location.longitude,
            )
        }
        val elapsedMs = if (previousRecordedAtMs == 0L) 0L else now - previousRecordedAtMs
        val speedMetersPerSecond =
            elapsedMs.takeIf { it > 0L }?.let { distanceMovedMeters / (it / 1_000.0) }
        val routeIndexDelta = if (previousNearestIndex == null) {
            0
        } else {
            nearestIndex - previousNearestIndex
        }
        lastMovementLocation = Location(location)
        lastMovementNearestIndex = nearestIndex
        lastMovementRecordedAtMs = now

        val isTransitLike =
            (
                speedMetersPerSecond != null &&
                    distanceMovedMeters >= USER_MOVEMENT_MIN_DISTANCE_METERS &&
                    speedMetersPerSecond >= USER_TRANSIT_LIKE_SPEED_MPS
            ) ||
                (
                    routeIndexDelta > 0 &&
                        distanceMovedMeters >= USER_ROUTE_PROGRESS_MIN_DISTANCE_METERS
                )
        return UserMovementState(
            routeIndexDelta = routeIndexDelta,
            isTransitLike = isTransitLike,
        )
    }

    private fun hasBusReachedBoardingStop(
        busStopsUntilBoarding: Int?,
        boardingEtaText: String,
        boardingEtaSeconds: Int?,
    ): Boolean {
        if (busStopsUntilBoarding != null && busStopsUntilBoarding <= 0) {
            if (isImmediateEtaText(boardingEtaText)) {
                return true
            }
            if (isLikelyBoardingArrival(etaSeconds = boardingEtaSeconds, etaText = boardingEtaText)) {
                return true
            }
        }
        return false
    }

    private fun buildNearestStatusText(
        session: TrackingSession,
        nearestStop: TrackingStop,
        nearestEtaText: String,
        busStopsAway: Int?,
    ): String {
        val parts = mutableListOf<String>()
        if (session.pathName.isNotBlank()) {
            parts += session.pathName
        }
        parts += "最近站牌 ${nearestStop.stopName}"
        if (nearestEtaText != "--") {
            parts += nearestEtaText
        }
        buildBusDistanceSummary(busStopsAway)?.let(parts::add)
        return parts.joinToString(" · ")
    }

    private fun buildWaitingBoardingText(
        session: TrackingSession,
        boardingStop: TrackingStop,
        destinationStop: TrackingStop,
        busStopsUntilBoarding: Int?,
    ): String {
        val parts = mutableListOf<String>()
        if (session.pathName.isNotBlank()) {
            parts += session.pathName
        }
        parts += "尚未上車"
        parts += "上車站 ${boardingStop.stopName}"
        parts += "目的地 ${destinationStop.stopName}"
        buildBusDistanceSummary(busStopsUntilBoarding)?.let(parts::add)
        return parts.joinToString(" · ")
    }

    private fun buildBusDistanceSummary(stopsAway: Int?): String? {
        return when (stopsAway) {
            null -> null
            0 -> "公車即將進站"
            else -> "公車還有 $stopsAway 站"
        }
    }

    private fun displayEtaText(
        liveStopState: LiveStopState?,
        preferredVehicleId: String? = null,
    ): String {
        val selectedEta = findEtaForVehicle(liveStopState, preferredVehicleId)
        return composeEtaText(
            seconds = selectedEta?.seconds ?: liveStopState?.seconds,
            message = selectedEta?.message ?: liveStopState?.message,
        )
    }

    private fun displayShortEtaText(
        liveStopState: LiveStopState?,
        preferredVehicleId: String? = null,
    ): String {
        val selectedEta = findEtaForVehicle(liveStopState, preferredVehicleId)
        return composeShortEtaText(
            seconds = selectedEta?.seconds ?: liveStopState?.seconds,
            message = selectedEta?.message ?: liveStopState?.message,
        )
    }

    private fun selectTrackedBusId(
        currentTrackedBusId: String?,
        nearestLiveStop: LiveStopState?,
        boardingLiveStop: LiveStopState?,
        destinationLiveStop: LiveStopState?,
        userBusLiveStop: LiveStopState? = null,
    ): String? {
        val normalizedCurrent = normalizeVehicleId(currentTrackedBusId)
        if (normalizedCurrent != null) {
            return normalizedCurrent
        }

        listOf(userBusLiveStop, nearestLiveStop, boardingLiveStop, destinationLiveStop).forEach { stopState ->
            firstKnownVehicleId(stopState)?.let { return it }
        }

        return normalizedCurrent
    }

    private fun firstKnownVehicleId(stopState: LiveStopState?): String? {
        stopState ?: return null
        stopState.etaEntries.firstNotNullOfOrNull { entry ->
            normalizeVehicleId(entry.vehicleId)
        }?.let { return it }
        return stopState.vehicleIds.firstNotNullOfOrNull { vehicleId ->
            normalizeVehicleId(vehicleId)
        }
    }

    private fun isVehicleSeenAtStop(
        stopState: LiveStopState?,
        normalizedVehicleId: String,
    ): Boolean {
        stopState ?: return false
        if (stopState.vehicleIds.any { normalizeVehicleId(it) == normalizedVehicleId }) {
            return true
        }
        return stopState.etaEntries.any { etaEntry ->
            normalizeVehicleId(etaEntry.vehicleId) == normalizedVehicleId
        }
    }

    private fun findEtaForVehicle(
        stopState: LiveStopState?,
        preferredVehicleId: String?,
    ): LiveEtaEntry? {
        val normalizedVehicleId = normalizeVehicleId(preferredVehicleId) ?: return null
        return stopState?.etaEntries?.firstOrNull { etaEntry ->
            normalizeVehicleId(etaEntry.vehicleId) == normalizedVehicleId
        }
    }

    private fun normalizeVehicleId(vehicleId: String?): String? {
        val cleaned = vehicleId
            ?.trim()
            ?.replace(" ", "")
            .orEmpty()
        if (cleaned.isEmpty()) {
            return null
        }
        return cleaned.uppercase()
    }

    private fun resolveEtaSeconds(
        stopState: LiveStopState?,
        preferredVehicleId: String? = null,
    ): Int? {
        val selectedEta = findEtaForVehicle(stopState, preferredVehicleId)
        return selectedEta?.seconds ?: stopState?.seconds
    }

    private fun isLikelyBoardingArrival(
        etaSeconds: Int?,
        etaText: String?,
    ): Boolean {
        if (isImmediateEtaText(etaText)) {
            return true
        }
        return etaSeconds != null && etaSeconds <= BOARDING_ARRIVAL_MAX_ETA_SECONDS
    }

    private fun composeEtaText(seconds: Int?, message: String?): String {
        val trimmedMessage = message?.trim().orEmpty()
        if (trimmedMessage.isNotEmpty()) {
            return when {
                trimmedMessage.contains("進站") || trimmedMessage.contains("到站") -> "進站中"
                trimmedMessage.contains("即將") -> "即將進站"
                trimmedMessage.contains("未發車") -> "未發車"
                trimmedMessage.contains("末班") -> "末班已過"
                else -> trimmedMessage
            }
        }

        val etaSeconds = seconds ?: return "--"
        if (etaSeconds <= 0) {
            return "進站中"
        }
        if (etaSeconds < 60) {
            return "即將進站"
        }
        return "${etaSeconds / 60} 分"
    }

    private fun composeShortEtaText(seconds: Int?, message: String?): String {
        val trimmedMessage = message?.trim().orEmpty()
        if (trimmedMessage.isNotEmpty()) {
            return when {
                trimmedMessage.contains("進站") || trimmedMessage.contains("到站") -> "進站"
                trimmedMessage.contains("即將") -> "即將"
                trimmedMessage.contains("未發車") -> "未發"
                trimmedMessage.contains("末班") -> "末班"
                else -> trimmedMessage.take(4)
            }
        }

        val etaSeconds = seconds ?: return "--"
        if (etaSeconds <= 0) {
            return "進站"
        }
        if (etaSeconds < 60) {
            return "<1分"
        }
        return "${etaSeconds / 60}分"
    }

    private fun isImmediateEtaText(etaText: String?): Boolean {
        val value = etaText?.trim().orEmpty()
        return value.contains("進站") || value.contains("即將")
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

    private fun applyShortCriticalPresentation(
        builder: NotificationCompat.Builder,
        shortCriticalText: String?,
    ) {
        val trimmed = shortCriticalText?.trim().orEmpty()
        val countdownWhen = parseShortCriticalCountdownWhen(trimmed)
        if (countdownWhen != null) {
            builder
                .setShowWhen(true)
                .setWhen(countdownWhen)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
            return
        }
        builder
            .setShowWhen(false)
            .setUsesChronometer(false)
        trimmed.takeIf { it.isNotEmpty() }?.let(builder::setShortCriticalText)
    }

    private fun applyShortCriticalPresentation(
        builder: Notification.Builder,
        shortCriticalText: String?,
    ) {
        val trimmed = shortCriticalText?.trim().orEmpty()
        val countdownWhen = parseShortCriticalCountdownWhen(trimmed)
        if (countdownWhen != null) {
            builder
                .setShowWhen(true)
                .setWhen(countdownWhen)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
            return
        }
        builder
            .setShowWhen(false)
            .setUsesChronometer(false)
        trimmed.takeIf { it.isNotEmpty() }?.let(builder::setShortCriticalText)
    }

    private fun parseShortCriticalCountdownWhen(shortCriticalText: String): Long? {
        val match = SHORT_CRITICAL_COUNTDOWN_REGEX.matchEntire(shortCriticalText) ?: return null
        val minutes = match.groupValues[1].toLongOrNull() ?: return null
        val seconds = match.groupValues[2].toLongOrNull() ?: return null
        val totalMillis = (minutes * 60L + seconds) * 1_000L
        return System.currentTimeMillis() + totalMillis
    }


    private fun buildProgressPointPositions(progressMax: Int): List<Int> {
        if (progressMax <= 0) {
            return emptyList()
        }
        if (progressMax <= MAX_PROGRESS_POINTS) {
            return (1..progressMax).toList()
        }
        val positions = linkedSetOf(1)
        val lastIndex = MAX_PROGRESS_POINTS - 1
        for (index in 1 until lastIndex) {
            val progress = 1 + ((progressMax - 1).toDouble() * index / lastIndex).roundToInt()
            positions += progress.coerceIn(1, progressMax)
        }
        positions += progressMax
        return positions.toList().sorted()
    }

    private fun buildStoppedNotification(): Notification {
        return NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle("YABus")
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun buildCompatTrackingNotification(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): Notification {
        val builder = NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setContentIntent(createOpenRoutePendingIntent(session))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPublicVersion(buildPublicTrackingNotification(snapshot))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(
                NotificationCompat.Action.Builder(
                    0,
                    "停止",
                    createStopPendingIntent(),
                ).build(),
            )

        applyShortCriticalPresentation(builder, snapshot.shortCriticalText)

        requestPromotedOngoing(builder)
        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null && progressMax > 0) {
            val clampedValue = progressValue.coerceIn(0, progressMax)
            val progressPoints = buildProgressPointPositions(progressMax)
            builder.setProgress(progressMax, clampedValue, false)
            val progressStyle = NotificationCompat.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(clampedValue)
                .setProgressTrackerIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_progress_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    progressPoints.mapTo(mutableListOf()) { position ->
                        NotificationCompat.ProgressStyle.Point(position)
                            .setColor(PROGRESS_POINT_COLOR)
                    },
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
            .setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setContentIntent(createOpenRoutePendingIntent(session))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPublicVersion(buildPublicTrackingNotification(snapshot))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "停止",
                    createStopPendingIntent(),
                ).build(),
            )

        applyShortCriticalPresentation(builder, snapshot.shortCriticalText)

        requestPromotedOngoing(builder)
        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null && progressMax > 0) {
            val clampedValue = progressValue.coerceIn(0, progressMax)
            val progressPoints = buildProgressPointPositions(progressMax)
            builder.setProgress(progressMax, clampedValue, false)
            val progressStyle = Notification.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(clampedValue)
                .setProgressTrackerIcon(
                    Icon.createWithResource(this, R.drawable.ic_progress_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        Notification.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    progressPoints.mapTo(mutableListOf()) { position ->
                        Notification.ProgressStyle.Point(position)
                            .setColor(PROGRESS_POINT_COLOR)
                    },
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
            .setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setSubText(snapshot.subText)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }

    private fun buildLegacyTrackingNotification(snapshot: TrackingSnapshot): android.app.Notification {
        val currentSession = session ?: return NotificationCompat.Builder(
            this,
            TRACKING_CHANNEL_ID,
        ).setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle("YABus")
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        val builder = NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_status_bus)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.content)
            .setContentIntent(createOpenRoutePendingIntent(currentSession))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
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
        applyShortCriticalPresentation(builder, snapshot.shortCriticalText)

        val progressMax = snapshot.progressMax
        val progressValue = snapshot.progressValue
        if (progressMax != null && progressValue != null && progressMax > 0) {
            val clampedValue = progressValue.coerceIn(0, progressMax)
            val progressPoints = buildProgressPointPositions(progressMax)
            builder.setProgress(progressMax, clampedValue, false)
            val progressStyle = NotificationCompat.ProgressStyle()
                .setStyledByProgress(true)
                .setProgress(clampedValue)
                .setProgressTrackerIcon(
                    IconCompat.createWithResource(this, R.drawable.ic_progress_bus),
                )
                .setProgressSegments(
                    mutableListOf(
                        NotificationCompat.ProgressStyle.Segment(progressMax),
                    ),
                )
                .setProgressPoints(
                    progressPoints.mapTo(mutableListOf()) { position ->
                        NotificationCompat.ProgressStyle.Point(position)
                            .setColor(PROGRESS_POINT_COLOR)
                    },
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

    private fun maybeSendTripAlerts(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        if (snapshot.passedDestinationByStops != null) {
            if (maybeSendOvershotAlert(session, snapshot)) {
                return
            }
            maybePauseAfterArrivalGrace()
            return
        }
        if (snapshot.hasBoarded && snapshot.destinationName == null) {
            if (
                lastWentBackgroundAtMs > 0L &&
                System.currentTimeMillis() - lastWentBackgroundAtMs <
                    BACKGROUND_AUTO_PAUSE_GRACE_MS
            ) {
                return
            }
            maybeSendDestinationSetupPrompt(session, snapshot)
            pauseTracking(
                PAUSE_REASON_BOARDED_NO_DESTINATION,
                preserveAlertNotification = true,
            )
            return
        }
        if (!snapshot.hasBoarded) {
            maybeSendBoardingAlert(session, snapshot)
            maybeSendBoardingCheckPrompt(session, snapshot)
            return
        }
        maybeSendDestinationAlert(session, snapshot)
        maybePauseAfterArrivalGrace()
    }

    private fun maybeSendBoardingAlert(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        if (boardingAlertSent) {
            return
        }
        val boardingName = snapshot.boardingName ?: return
        val destinationName = snapshot.destinationName ?: return
        val busStopsAway = snapshot.boardingStopsAway
        val shouldAlert = (busStopsAway != null && busStopsAway <= 1) ||
            isImmediateEtaText(snapshot.boardingEtaText)
        if (!shouldAlert) {
            return
        }

        boardingAlertSent = true
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_status_bus)
                .setContentTitle("準備上車")
                .setContentText("$boardingName 的公車快到了")
                .setSubText(session.pathName)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPublicVersion(
                    NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                        .setSmallIcon(R.drawable.ic_status_bus)
                        .setContentTitle("準備上車")
                        .setContentText("$boardingName 的公車快到了")
                        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                        .build(),
                )
                .setStyle(
                    NotificationCompat.BigTextStyle().bigText(
                        "$boardingName 的公車快到了，請準備上車。上車後會繼續提醒你前往 $destinationName。",
                    ),
                )
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(createOpenRoutePendingIntent(session))
                .build(),
        )
    }

    private fun maybeSendBoardingCheckPrompt(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        if (!session.backgroundLocationAlwaysGranted || snapshot.hasBoarded) {
            return
        }
        if (boardingCheckPromptSent || !snapshot.boardingPromptEligible) {
            return
        }
        val now = System.currentTimeMillis()
        if (now < boardingCheckSnoozeUntilMs) {
            return
        }
        val boardingName = snapshot.boardingName ?: return

        boardingCheckPromptSent = true
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_status_bus)
                .setContentTitle("你有上車嗎？")
                .setContentText("$boardingName 的那台車已經過站了。")
                .setSubText(session.pathName)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(createOpenRoutePendingIntent(session))
                .addAction(
                    NotificationCompat.Action.Builder(
                        0,
                        "我已上車",
                        createMarkBoardedPendingIntent(),
                    ).build(),
                )
                .addAction(
                    NotificationCompat.Action.Builder(
                        0,
                        "還沒上車",
                        createNotBoardedPendingIntent(),
                    ).build(),
                )
                .build(),
        )
    }

    private fun maybeSendDestinationSetupPrompt(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        if (destinationSetupPromptSent) {
            return
        }
        destinationSetupPromptSent = true
        val boardingName = snapshot.boardingName
        val contentText = if (boardingName.isNullOrBlank()) {
            "已偵測到可能上車，要設定下車站嗎？"
        } else {
            "已偵測在 $boardingName 上車，要設定下車站嗎？"
        }
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_status_bus)
                .setContentTitle("已偵測上車")
                .setContentText(contentText)
                .setSubText(session.pathName)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(createOpenRoutePendingIntent(session))
                .build(),
        )
    }

    private fun maybeSendDestinationAlert(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ) {
        val destinationName = snapshot.destinationName ?: return
        val remainingStops = snapshot.remainingStops ?: return
        val distanceMeters = snapshot.destinationDistanceMeters ?: return
        val now = System.currentTimeMillis()

        if (remainingStops <= 2 && destinationAlertStage < 1) {
            destinationAlertStage = 1
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_status_bus)
                    .setContentTitle("${session.routeName} 快到了")
                    .setContentText("$destinationName 還有 $remainingStops 站")
                    .setSubText(session.pathName)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setPublicVersion(
                        NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                            .setSmallIcon(R.drawable.ic_status_bus)
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
            arrivalDetectedAtMs = now
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_status_bus)
                    .setContentTitle("準備下車")
                    .setContentText("你已接近 $destinationName")
                    .setSubText(session.pathName)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setPublicVersion(
                        NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                            .setSmallIcon(R.drawable.ic_status_bus)
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
        } else if (destinationAlertStage >= 2 && arrivalDetectedAtMs == 0L) {
            arrivalDetectedAtMs = now
        }
    }

    private fun maybeSendOvershotAlert(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): Boolean {
        if (overshootAlertSent) {
            return true
        }
        if (arrivalDetectedAtMs == 0L) {
            return false
        }
        if (System.currentTimeMillis() - arrivalDetectedAtMs < OVERSHOOT_CONFIRM_DELAY_MS) {
            return false
        }
        val destinationName = snapshot.destinationName ?: return false
        val passedByStops = snapshot.passedDestinationByStops ?: return false
        val destinationDistanceMeters = snapshot.destinationDistanceMeters ?: return false
        val nearestStopDistanceMeters = snapshot.nearestStopDistanceMeters ?: return false
        if (
            destinationDistanceMeters <= DESTINATION_OVERSHOOT_DISTANCE_METERS ||
                nearestStopDistanceMeters > ROUTE_PROXIMITY_MAX_DISTANCE_METERS
        ) {
            return false
        }

        overshootAlertSent = true
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_status_bus)
                .setContentTitle("可能坐過站了")
                .setContentText("你已超過 $destinationName ${passedByStops} 站")
                .setSubText(session.pathName)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(createOpenRoutePendingIntent(session))
                .build(),
        )
        pauseTracking(
            PAUSE_REASON_OVERSHOT,
            preserveAlertNotification = true,
        )
        return true
    }

    private fun maybePauseAfterArrivalGrace() {
        if (arrivalDetectedAtMs == 0L || overshootAlertSent) {
            return
        }
        if (System.currentTimeMillis() - arrivalDetectedAtMs < ARRIVAL_AUTO_PAUSE_DELAY_MS) {
            return
        }
        pauseTracking(
            PAUSE_REASON_ARRIVED,
            preserveAlertNotification = true,
        )
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.deleteNotificationChannel(LEGACY_TRACKING_CHANNEL_ID)
        val defaultNotificationSound =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val defaultAudioAttributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        manager.createNotificationChannel(
            NotificationChannel(
                TRACKING_CHANNEL_ID,
                "背景乘車提醒",
                NotificationManager.IMPORTANCE_DEFAULT,
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
            action = ACTION_PAUSE
        }
        return PendingIntent.getService(
            this,
            404,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createMarkBoardedPendingIntent(): PendingIntent {
        val intent = Intent(this, RouteTripMonitorService::class.java).apply {
            action = ACTION_MARK_BOARDED
        }
        return PendingIntent.getService(
            this,
            405,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotBoardedPendingIntent(): PendingIntent {
        val intent = Intent(this, RouteTripMonitorService::class.java).apply {
            action = ACTION_NOT_BOARDED
        }
        return PendingIntent.getService(
            this,
            406,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        AppRuntimeStateStore.setAppInForeground(this, false)
        stopTracking()
        super.onTaskRemoved(rootIntent)
    }

    private fun pauseTracking(
        reason: String,
        explicitSession: TrackingSession? = null,
        preserveAlertNotification: Boolean = false,
    ) {
        val sessionToPause = explicitSession ?: session
        if (sessionToPause != null) {
            AppRuntimeStateStore.savePausedTripMonitor(this, sessionToPause, reason)
        }
        stopTracking(cancelAlertNotification = !preserveAlertNotification)
    }

    private fun stopTracking(cancelAlertNotification: Boolean = true) {
        foregroundStarted = false
        session = null
        latestLocation = null
        lastMovementLocation = null
        lastMovementNearestIndex = null
        lastMovementRecordedAtMs = 0L
        boardingAlertSent = false
        boardingCheckPromptSent = false
        boardingWindowOpen = false
        boardingWindowOpenedAtMs = 0L
        boardingCheckSnoozeUntilMs = 0L
        rideConfirmed = false
        rideConfirmationSamples = 0
        lastNearestStopIndex = null
        lastBusStopIndex = null
        activeBoardingVehicleId = null
        activeBoardingVehicleStopIndex = null
        activeBoardingVehicleLastSeenAtMs = 0L
        activeBoardingVehiclePassedAtMs = 0L
        trackedBusId = null
        destinationSetupPromptSent = false
        arrivalDetectedAtMs = 0L
        destinationAlertStage = 0
        overshootAlertSent = false
        refreshInFlight = false
        refreshPending = false
        lastRefreshStartedAtMs = 0L
        cachedLiveRouteId = null
        cachedLivePathId = null
        cachedLiveFetchedAtMs = 0L
        cachedLiveStops = emptyMap()
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
        notificationManager.cancel(TRACKING_NOTIFICATION_ID)
        if (cancelAlertNotification) {
            notificationManager.cancel(ALERT_NOTIFICATION_ID)
        }
        stopSelf()
    }

    private fun fetchLiveStopMap(session: TrackingSession): Map<Int, LiveStopState> {
        val routeId = session.routeId?.trim().orEmpty()
        if (routeId.isEmpty()) {
            return emptyMap()
        }
        val now = SystemClock.elapsedRealtime()
        synchronized(refreshLock) {
            if (
                cachedLiveRouteId == routeId &&
                cachedLivePathId == session.pathId &&
                cachedLiveFetchedAtMs != 0L &&
                now - cachedLiveFetchedAtMs < LIVE_STOP_CACHE_TTL_MS
            ) {
                return cachedLiveStops
            }
        }
        val liveStops = fetchLiveStopMapFromBackend(
            routeId = routeId,
            pathId = session.pathId,
        )
        synchronized(refreshLock) {
            cachedLiveRouteId = routeId
            cachedLivePathId = session.pathId
            cachedLiveFetchedAtMs = now
            cachedLiveStops = liveStops
        }
        return liveStops
    }

    private fun fetchLiveStopMapFromBackend(
        routeId: String,
        pathId: Int,
    ): Map<Int, LiveStopState> {
        val encodedRouteId = URLEncoder.encode(routeId, Charsets.UTF_8.name())
        val connection = URL("https://bus.avianjay.sbs/api/v1/routes/$encodedRouteId/realtime")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (YABus Android)")
        connection.doInput = true
        connection.useCaches = false

        return try {
            if (connection.responseCode !in 200..299) {
                return emptyMap()
            }
            val jsonText = connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                reader.readText()
            }
            parseBackendLiveStopMap(jsonText, pathId)
        } catch (_: Exception) {
            emptyMap()
        } finally {
            connection.disconnect()
        }
    }

    private fun parseBackendLiveStopMap(
        jsonText: String,
        pathId: Int,
    ): Map<Int, LiveStopState> {
        val root = JSONObject(jsonText)
        val paths = root.optJSONArray("paths") ?: return emptyMap()
        val result = mutableMapOf<Int, LiveStopState>()

        fun appendPath(pathObject: JSONObject) {
            val stops = pathObject.optJSONArray("stops") ?: return
            for (stopIndex in 0 until stops.length()) {
                val stopObject = stops.optJSONObject(stopIndex) ?: continue
                val stopId = parseStopId(stopObject.opt("stopid"))
                if (stopId <= 0) {
                    continue
                }
                val message = stopObject.opt("message")
                    ?.toString()
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
                val etaEntries = extractEtaEntries(stopObject.optJSONArray("etas"))
                result[stopId] = LiveStopState(
                    seconds = toIntOrNull(stopObject.opt("eta")),
                    message = message,
                    vehicleIds = extractVehicleIds(
                        buses = stopObject.optJSONArray("buses"),
                        etaEntries = etaEntries,
                    ),
                    etaEntries = etaEntries,
                )
            }
        }

        var matchedPath = false
        for (index in 0 until paths.length()) {
            val pathObject = paths.optJSONObject(index) ?: continue
            if (toIntOrNull(pathObject.opt("pathid")) == pathId) {
                matchedPath = true
                appendPath(pathObject)
            }
        }

        if (!matchedPath) {
            for (index in 0 until paths.length()) {
                val pathObject = paths.optJSONObject(index) ?: continue
                appendPath(pathObject)
            }
        }

        return result
    }

    private fun parseStopId(raw: Any?): Int {
        if (raw is Number) {
            return raw.toInt()
        }
        val text = raw?.toString()?.trim().orEmpty()
        val parsed = text.toIntOrNull()
        if (parsed != null) {
            return parsed
        }
        var hash = 17
        for (char in text) {
            hash = (hash * 31 + char.code) and 0x7fffffff
        }
        return hash
    }

    private fun toIntOrNull(raw: Any?): Int? {
        return when (raw) {
            is Number -> raw.toInt()
            else -> raw?.toString()?.trim()?.toIntOrNull()
        }
    }

    private fun extractEtaEntries(rawEtas: JSONArray?): List<LiveEtaEntry> {
        if (rawEtas == null) {
            return emptyList()
        }
        val result = mutableListOf<LiveEtaEntry>()
        for (index in 0 until rawEtas.length()) {
            val etaObject = rawEtas.optJSONObject(index) ?: continue
            val message = etaObject.opt("message")
                ?.toString()
                ?.trim()
                ?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
            val vehicleId = normalizeVehicleId(
                etaObject.opt("plate")
                    ?.toString()
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: etaObject.opt("vehicle_id")
                        ?.toString()
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() }
                    ?: etaObject.opt("id")
                        ?.toString()
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() },
            )
            val entry = LiveEtaEntry(
                seconds = toIntOrNull(etaObject.opt("eta")),
                message = message,
                vehicleId = vehicleId,
            )
            if (entry.seconds == null && entry.message == null && entry.vehicleId == null) {
                continue
            }
            result += entry
        }
        return result
    }

    private fun extractVehicleIds(
        buses: JSONArray?,
        etaEntries: List<LiveEtaEntry> = emptyList(),
    ): List<String> {
        val result = linkedSetOf<String>()
        if (buses != null) {
            for (index in 0 until buses.length()) {
                val busObject = buses.optJSONObject(index) ?: continue
                val vehicleId = normalizeVehicleId(
                    busObject.opt("id")
                        ?.toString()
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() }
                        ?: busObject.opt("vehicle_id")
                            ?.toString()
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() }
                        ?: busObject.opt("plate")
                            ?.toString()
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() },
                )
                if (vehicleId != null) {
                    result += vehicleId
                }
            }
        }
        etaEntries.mapNotNullTo(result) { entry ->
            normalizeVehicleId(entry.vehicleId)
        }
        return result.toList()
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

    private fun buildShortCriticalText(stopsAway: Int?, etaText: String): String? {
        val cleanEtaText = cleanStandaloneShortEtaText(etaText)
        if (stopsAway == null) {
            return cleanEtaText
        }
        if (stopsAway == 0 && cleanEtaText != null) {
            return cleanEtaText
        }

        val left = when (stopsAway) {
            0 -> "到站"
            else -> "${stopsAway}站"
        }
        val compact = when {
            cleanEtaText == null -> left
            else -> "$left|$cleanEtaText"
        }
        return compact.take(7)
    }

    private fun cleanStandaloneShortEtaText(etaText: String): String? {
        val trimmed = etaText.trim()
        if (trimmed.isEmpty() || trimmed == "--") {
            return null
        }
        return trimmed.take(7)
    }

    private fun buildLegacyShortCriticalText(stopsAway: Int?, etaText: String): String? {
        if (stopsAway == null && etaText == "--") {
            return null
        }

        if (stopsAway == 0 && etaText != "--") {
            return etaText.take(7)
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

    private fun findClosestBusIndexForBoarding(
        stops: List<TrackingStop>,
        liveStops: Map<Int, LiveStopState>,
        boardingIndex: Int,
    ): Int? {
        val busIndexes = stops.mapIndexedNotNull { index, stop ->
            val liveStop = liveStops[stop.stopId] ?: return@mapIndexedNotNull null
            if (isBusApproachingStop(liveStop)) {
                index
            } else {
                null
            }
        }
        return busIndexes
            .filter { it <= boardingIndex }
            .maxOrNull()
    }

    private fun findTrackedBusIndex(
        stops: List<TrackingStop>,
        liveStops: Map<Int, LiveStopState>,
        preferredVehicleId: String?,
    ): Int? {
        val normalizedVehicleId = normalizeVehicleId(preferredVehicleId) ?: return null
        return stops.indexOfFirst { stop ->
            isVehicleSeenAtStop(
                stopState = liveStops[stop.stopId],
                normalizedVehicleId = normalizedVehicleId,
            )
        }.takeIf { it >= 0 }
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
        return Build.VERSION.SDK_INT >= LIVE_UPDATE_SDK_INT
    }

    companion object {
        private const val ACTION_START_OR_UPDATE =
            "tw.avianjay.taiwanbus.flutter.action.START_OR_UPDATE_TRIP_MONITOR"
        private const val ACTION_SET_APP_FOREGROUND =
            "tw.avianjay.taiwanbus.flutter.action.SET_TRIP_MONITOR_APP_FOREGROUND"
        private const val ACTION_PAUSE =
            "tw.avianjay.taiwanbus.flutter.action.PAUSE_TRIP_MONITOR"
        private const val ACTION_MARK_BOARDED =
            "tw.avianjay.taiwanbus.flutter.action.MARK_BOARDED"
        private const val ACTION_NOT_BOARDED =
            "tw.avianjay.taiwanbus.flutter.action.NOT_BOARDED"
        private const val ACTION_RESUME =
            "tw.avianjay.taiwanbus.flutter.action.RESUME_TRIP_MONITOR"
        private const val ACTION_STOP =
            "tw.avianjay.taiwanbus.flutter.action.STOP_TRIP_MONITOR"

        private const val EXTRA_SESSION_JSON = "session_json"
        private const val EXTRA_APP_IN_FOREGROUND = "app_in_foreground"
        private const val EXTRA_PAUSE_REASON = "pause_reason"

        private const val LEGACY_TRACKING_CHANNEL_ID = "trip_monitor_tracking"
        private const val TRACKING_CHANNEL_ID = "trip_monitor_tracking_v2"
        private const val ALERT_CHANNEL_ID = "trip_monitor_alerts"
        private const val TRACKING_NOTIFICATION_ID = 6021
        private const val ALERT_NOTIFICATION_ID = 6022

        private const val POLL_INTERVAL_MS = 15_000L
        private const val MIN_REFRESH_INTERVAL_MS = 2_000L
        private const val LIVE_STOP_CACHE_TTL_MS = 2_000L
        private const val LOCATION_UPDATE_INTERVAL_MS = 12_000L
        private const val LOCATION_MIN_UPDATE_INTERVAL_MS = 6_000L
        private const val BOARDING_STOP_RADIUS_METERS = 180.0
        private const val BOARDING_CONFIRM_DISTANCE_METERS = 250.0
        private const val BOARDING_ARRIVAL_MAX_ETA_SECONDS = 180
        private const val BOARDING_CHECK_PROMPT_MAX_ETA_SECONDS = 180
        private const val REQUIRED_RIDE_CONFIRMATION_SAMPLES = 2
        private const val BACKGROUND_AUTO_PAUSE_GRACE_MS = 90_000L
        private const val BOARDING_CHECK_PROMPT_DELAY_MS = 45_000L
        private const val BOARDING_CHECK_SNOOZE_MS = 180_000L
        private const val BOARDING_CHECK_AFTER_PASS_DELAY_MS = 20_000L
        private const val ACTIVE_BOARDING_VEHICLE_STALE_MS = 90_000L
        private const val USER_NEARBY_STOP_COUNT = 2
        private const val USER_MOVEMENT_MIN_DISTANCE_METERS = 35.0
        private const val USER_ROUTE_PROGRESS_MIN_DISTANCE_METERS = 45.0
        private const val USER_TRANSIT_LIKE_SPEED_MPS = 4.2
        private const val MAX_PROGRESS_POINTS = 8
        private const val PROGRESS_POINT_COLOR = 0x80000000.toInt()
        private const val OVERSHOOT_CONFIRM_DELAY_MS = 45_000L
        private const val ARRIVAL_AUTO_PAUSE_DELAY_MS = 60_000L
        private const val ROUTE_PROXIMITY_MAX_DISTANCE_METERS = 300.0
        private const val DESTINATION_OVERSHOOT_DISTANCE_METERS = 300.0
        private const val LIVE_UPDATE_SDK_INT = 36
        private const val PAUSE_REASON_USER = "user"
        private const val PAUSE_REASON_ARRIVED = "arrived"
        private const val PAUSE_REASON_OVERSHOT = "overshot"
        private const val PAUSE_REASON_BOARDED_NO_DESTINATION = "boarded_no_destination"
        private val SHORT_CRITICAL_COUNTDOWN_REGEX = Regex("^\\(?([0-9]{2}):([0-9]{2})\\)?$")

        private fun parseSessionJson(sessionJson: String): TrackingSession? {
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
                    routeId = root.optString("routeId", "")
                        .trim()
                        .takeIf { it.isNotEmpty() },
                    routeName = root.optString("routeName", "YABus"),
                    pathId = root.optInt("pathId", 0),
                    pathName = root.optString("pathName", ""),
                    appInForeground = root.optBoolean("appInForeground", true),
                    backgroundLocationAlwaysGranted =
                        root.optBoolean("backgroundLocationAlwaysGranted", true),
                    initialLatitude = root.optDouble("initialLatitude", Double.NaN)
                        .takeUnless { it.isNaN() },
                    initialLongitude = root.optDouble("initialLongitude", Double.NaN)
                        .takeUnless { it.isNaN() },
                    boardingStopId = root.optInt("boardingStopId", -1)
                        .takeIf { it > 0 },
                    boardingStopName = root.optString("boardingStopName", "")
                        .takeIf { it.isNotBlank() },
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

        fun parseSessionPayload(session: Map<String, Any?>): TrackingSession? {
            return try {
                parseSessionJson(JSONObject(session).toString())
            } catch (_: Exception) {
                null
            }
        }

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

        fun pause(context: Context, session: Map<String, Any?>?, reason: String) {
            val intent = Intent(context, RouteTripMonitorService::class.java).apply {
                action = ACTION_PAUSE
                putExtra(EXTRA_PAUSE_REASON, reason)
                session?.let { putExtra(EXTRA_SESSION_JSON, JSONObject(it).toString()) }
            }
            context.startService(intent)
        }

        fun resume(context: Context) {
            val intent = Intent(context, RouteTripMonitorService::class.java).apply {
                action = ACTION_RESUME
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
    val routeId: String?,
    val routeName: String,
    val pathId: Int,
    val pathName: String,
    val appInForeground: Boolean,
    val backgroundLocationAlwaysGranted: Boolean,
    val initialLatitude: Double?,
    val initialLongitude: Double?,
    val boardingStopId: Int?,
    val boardingStopName: String?,
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
    val etaEntries: List<LiveEtaEntry> = emptyList(),
)

data class LiveEtaEntry(
    val seconds: Int?,
    val message: String?,
    val vehicleId: String?,
)

data class TrackingSnapshot(
    val title: String,
    val content: String,
    val subText: String,
    val progressMax: Int?,
    val progressValue: Int?,
    val shortCriticalText: String? = null,
    val hasBoarded: Boolean = false,
    val boardingName: String? = null,
    val boardingEtaText: String? = null,
    val boardingEtaSeconds: Int? = null,
    val boardingStopsAway: Int? = null,
    val boardingDistanceMeters: Double? = null,
    val boardingVehicleId: String? = null,
    val boardingVehiclePassedStop: Boolean = false,
    val boardingPromptEligible: Boolean = false,
    val destinationName: String? = null,
    val remainingStops: Int? = null,
    val destinationDistanceMeters: Double? = null,
    val passedDestinationByStops: Int? = null,
    val nearestStopDistanceMeters: Double? = null,
)

data class VehicleCandidate(
    val vehicleId: String,
    val stopIndex: Int,
    val distanceMeters: Double,
    val etaSeconds: Int?,
)

data class UserMovementState(
    val routeIndexDelta: Int = 0,
    val isTransitLike: Boolean = false,
)

data class RideStateUpdate(
    val hasBoarded: Boolean = false,
    val boardingVehiclePassedStop: Boolean = false,
    val boardingPromptEligible: Boolean = false,
)
