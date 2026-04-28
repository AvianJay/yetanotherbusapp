package tw.avianjay.taiwanbus.flutter

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.tasks.Tasks
import java.io.File
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class SmartRouteNotificationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result {
        return try {
            SmartRouteNotificationSupport.ensureChannel(applicationContext)

            val settings = SmartRouteNotificationSupport.loadSettings(applicationContext)
                ?: return Result.success()
            if (!settings.enableNotifications) {
                return Result.success()
            }
            if (!SmartRouteNotificationSupport.canPostNotifications(applicationContext)) {
                return Result.success()
            }
            if (AppRuntimeStateStore.isAppInForeground(applicationContext)) {
                return Result.success()
            }

            val profiles = SmartRouteNotificationSupport
                .loadProfiles(applicationContext)
                .filter { it.provider == settings.provider }
            val now = System.currentTimeMillis()
            val candidate = SmartRouteNotificationSupport.chooseProfileForNow(
                profiles = profiles,
                nowMs = now,
            ) ?: return Result.success()
            if (SmartRouteNotificationSupport.wasRecentlyInteracted(candidate, now)) {
                return Result.success()
            }

            val currentLocation = SmartRouteNotificationSupport.loadCurrentLocation(
                applicationContext,
            ) ?: return Result.success()
            val routeData = SmartRouteNotificationSupport.loadRouteData(
                context = applicationContext,
                provider = candidate.provider,
                routeKey = candidate.routeKey,
                fallbackRouteName = candidate.routeName,
            ) ?: return Result.success()
            val nearestStop = SmartRouteNotificationSupport.findNearestStop(
                location = currentLocation,
                routeData = routeData,
            ) ?: return Result.success()
            val liveStop = SmartRouteNotificationSupport.fetchLiveStop(
                routeId = routeData.routeId,
                preferredPathId = nearestStop.pathId,
                stopId = nearestStop.stopId,
            ) ?: return Result.success()
            if (!SmartRouteNotificationSupport.shouldNotify(liveStop)) {
                return Result.success()
            }
            if (!SmartRouteNotificationSupport.shouldDeliverNotification(
                    context = applicationContext,
                    provider = candidate.provider,
                    routeKey = candidate.routeKey,
                    pathId = nearestStop.pathId,
                    stopId = nearestStop.stopId,
                    nowMs = now,
                )
            ) {
                return Result.success()
            }

            SmartRouteNotificationSupport.showNotification(
                context = applicationContext,
                profile = candidate,
                routeData = routeData,
                nearestStop = nearestStop,
                liveStop = liveStop,
                distanceMeters = nearestStop.distanceMeters,
                nowMs = now,
            )
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }
}

private object SmartRouteNotificationSupport {
    private const val MIN_TOTAL_OPENS_FOR_RECOMMENDATION = 3
    private const val MIN_RELEVANT_INTERACTIONS_FOR_RECOMMENDATION = 2
    private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val SETTINGS_KEY = "flutter.app_settings"
    private const val SETTINGS_FALLBACK_KEY = "app_settings"
    private const val ROUTE_USAGE_KEY = "flutter.route_usage_profiles"
    private const val ROUTE_USAGE_FALLBACK_KEY = "route_usage_profiles"
    private const val NOTIFICATION_PREFERENCES_NAME = "smart_route_notifications"
    private const val LAST_NOTIFIED_KEY_PREFIX = "last_notified_"
    private const val CHANNEL_ID = "smart_route_recommendation"
    private const val CHANNEL_NAME = "智慧推薦提醒"
    private const val CHANNEL_DESCRIPTION =
        "在你常查看某條路線的時間點附近，依最近站牌到站時間主動提醒。"
    private const val ROUTE_REQUEST_TIMEOUT_MS = 10_000
    private const val API_BASE_URL = "https://bus.avianjay.sbs"
    private const val NOTIFICATION_COOLDOWN_MS = 75 * 60 * 1000L
    private const val RECENT_INTERACTION_SUPPRESSION_MS = 30 * 60 * 1000L

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = CHANNEL_DESCRIPTION
                enableLights(true)
                enableVibration(true)
            },
        )
    }

    fun loadSettings(context: Context): SmartRouteSettings? {
        val root = loadFlutterJsonObject(
            context = context,
            primaryKey = SETTINGS_KEY,
            fallbackKey = SETTINGS_FALLBACK_KEY,
        ) ?: return null
        return SmartRouteSettings(
            provider = root.optString("provider", "twn"),
            enableNotifications = root.optBoolean("enableSmartRouteNotifications", false),
        )
    }

    fun loadProfiles(context: Context): List<SmartRouteProfile> {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(ROUTE_USAGE_KEY, null)
            ?: preferences.getString(ROUTE_USAGE_FALLBACK_KEY, null)
            ?: return emptyList()
        val array = try {
            JSONArray(raw)
        } catch (_: Exception) {
            return emptyList()
        }

        val result = mutableListOf<SmartRouteProfile>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val routeKey = item.optInt("routeKey", 0)
            if (routeKey <= 0) {
                continue
            }
            val hourlyOpens = mutableMapOf<Int, Int>()
            val hourlyObject = item.optJSONObject("hourlyOpens")
            hourlyObject?.keys()?.forEach { key ->
                val hour = key.toIntOrNull() ?: return@forEach
                if (hour !in 0..23) {
                    return@forEach
                }
                val count = hourlyObject.optInt(key, 0)
                if (count > 0) {
                    hourlyOpens[hour] = count
                }
            }
            val hourlySelections = mutableMapOf<Int, Int>()
            val selectionObject = item.optJSONObject("hourlySelections")
            selectionObject?.keys()?.forEach { key ->
                val hour = key.toIntOrNull() ?: return@forEach
                if (hour !in 0..23) {
                    return@forEach
                }
                val count = selectionObject.optInt(key, 0)
                if (count > 0) {
                    hourlySelections[hour] = count
                }
            }
            result += SmartRouteProfile(
                provider = item.optString("provider", "twn"),
                routeKey = routeKey,
                routeName = item.optString("routeName", "").trim(),
                totalOpens = item.optInt("totalOpens", 0),
                lastOpenedAtMs = item.optLong("lastOpenedAtMs", 0L),
                totalSelections = item.optInt("totalSelections", 0),
                lastSelectedAtMs = item.optLong("lastSelectedAtMs", 0L),
                hourlyOpens = hourlyOpens,
                hourlySelections = hourlySelections,
            )
        }
        return result
    }

    fun chooseProfileForNow(
        profiles: List<SmartRouteProfile>,
        nowMs: Long,
    ): SmartRouteProfile? {
        val now = java.util.Calendar.getInstance().apply {
            timeInMillis = nowMs
        }
        val currentHour = now.get(java.util.Calendar.HOUR_OF_DAY)
        val previousHour = (currentHour + 23) % 24
        val nextHour = (currentHour + 1) % 24

        return profiles
            .filter {
                hasEnoughHistoryForRecommendation(
                    profile = it,
                    currentHour = currentHour,
                    previousHour = previousHour,
                    nextHour = nextHour,
                )
            }
            .maxByOrNull { profile ->
                scoreProfile(profile, currentHour, previousHour, nextHour, nowMs)
            }
    }

    fun wasRecentlyInteracted(profile: SmartRouteProfile, nowMs: Long): Boolean {
        val lastInteractionAt = profile.latestInteractionAtMs
        if (lastInteractionAt <= 0L) {
            return false
        }
        return nowMs - lastInteractionAt < RECENT_INTERACTION_SUPPRESSION_MS
    }

    fun loadCurrentLocation(context: Context): Location? {
        if (!hasLocationPermission(context)) {
            return null
        }

        return try {
            val client = LocationServices.getFusedLocationProviderClient(context)
            val lastKnown = try {
                Tasks.await(client.lastLocation, 5, TimeUnit.SECONDS)
            } catch (_: Exception) {
                null
            }
            if (lastKnown != null) {
                return lastKnown
            }

            val tokenSource = CancellationTokenSource()
            Tasks.await(
                client.getCurrentLocation(
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                    tokenSource.token,
                ),
                8,
                TimeUnit.SECONDS,
            )
        } catch (_: Exception) {
            null
        }
    }

    fun loadRouteData(
        context: Context,
        provider: String,
        routeKey: Int,
        fallbackRouteName: String,
    ): SmartRouteData? {
        val databaseFile = resolveDatabaseFile(context, provider) ?: return null
        if (!databaseFile.exists()) {
            return null
        }

        val database = SQLiteDatabase.openDatabase(
            databaseFile.path,
            null,
            SQLiteDatabase.OPEN_READONLY,
        )
        return try {
            var routeId: String? = null
            val routeName = database.rawQuery(
                "SELECT route_id, route_name FROM routes WHERE route_key = ? LIMIT 1",
                arrayOf(routeKey.toString()),
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    routeId = cursor.getString(0)
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() }
                    cursor.getString(1).orEmpty()
                } else {
                    fallbackRouteName
                }
            }

            val pathNames = linkedMapOf<Int, String>()
            database.rawQuery(
                "SELECT path_id, path_name FROM paths WHERE route_key = ? ORDER BY path_id ASC",
                arrayOf(routeKey.toString()),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    pathNames[cursor.getInt(0)] = cursor.getString(1).orEmpty()
                }
            }

            val stops = loadStopsFromDatabase(database, routeKey)
            if (stops.isEmpty() || routeId.isNullOrEmpty()) {
                null
            } else {
                SmartRouteData(
                    provider = provider,
                    routeKey = routeKey,
                    routeId = routeId!!,
                    routeName = routeName.ifBlank { fallbackRouteName },
                    pathNames = pathNames,
                    stops = stops.sortedWith(compareBy({ it.pathId }, { it.sequence })),
                )
            }
        } finally {
            database.close()
        }
    }

    fun findNearestStop(
        location: Location,
        routeData: SmartRouteData,
    ): SmartNearestStop? {
        var bestStop: SmartNearestStop? = null
        for (stop in routeData.stops) {
            if (stop.lat == 0.0 || stop.lon == 0.0) {
                continue
            }
            val results = FloatArray(1)
            Location.distanceBetween(
                location.latitude,
                location.longitude,
                stop.lat,
                stop.lon,
                results,
            )
            val distance = results[0].toDouble()
            if (bestStop == null || distance < bestStop.distanceMeters) {
                bestStop = SmartNearestStop(
                    pathId = stop.pathId,
                    stopId = stop.stopId,
                    stopName = stop.stopName,
                    distanceMeters = distance,
                )
            }
        }
        return bestStop
    }

    fun fetchLiveStop(
        routeId: String,
        preferredPathId: Int,
        stopId: Int,
    ): SmartLiveStop? {
        val encodedRouteId = URLEncoder.encode(routeId, Charsets.UTF_8.name())
        val connection = URL("$API_BASE_URL/api/v1/routes/$encodedRouteId/realtime")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = ROUTE_REQUEST_TIMEOUT_MS
        connection.readTimeout = ROUTE_REQUEST_TIMEOUT_MS
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", NativeApiUserAgent.value())
        connection.doInput = true
        connection.useCaches = false

        return try {
            if (connection.responseCode !in 200..299) {
                null
            } else {
                val jsonText = connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    reader.readText()
                }
                parseLiveStopMap(jsonText, preferredPathId)[stopId]
            }
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    fun shouldNotify(liveStop: SmartLiveStop): Boolean {
        val message = liveStop.msg?.trim().orEmpty()
        if (message.isNotEmpty()) {
            return true
        }
        val seconds = liveStop.sec ?: return false
        return seconds <= 20 * 60
    }

    fun shouldDeliverNotification(
        context: Context,
        provider: String,
        routeKey: Int,
        pathId: Int,
        stopId: Int,
        nowMs: Long,
    ): Boolean {
        val preferences = notificationPreferences(context)
        val key = LAST_NOTIFIED_KEY_PREFIX + listOf(provider, routeKey, pathId, stopId).joinToString("_")
        val lastNotified = preferences.getLong(key, 0L)
        return nowMs - lastNotified >= NOTIFICATION_COOLDOWN_MS
    }

    fun showNotification(
        context: Context,
        profile: SmartRouteProfile,
        routeData: SmartRouteData,
        nearestStop: SmartNearestStop,
        liveStop: SmartLiveStop,
        distanceMeters: Double,
        nowMs: Long,
    ) {
        val contentIntent = PendingIntent.getActivity(
            context,
            profile.routeKey * 173 + nearestStop.stopId,
            AppLaunchConstants.createRouteDetailIntent(
                context = context,
                provider = profile.provider,
                routeKey = profile.routeKey,
                pathId = nearestStop.pathId,
                stopId = nearestStop.stopId,
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = "智慧推薦：${routeData.routeName.ifBlank { profile.routeName.ifBlank { "路線" } }}"
        val etaText = formatEtaText(liveStop)
        val contentText = "最近站牌 ${nearestStop.stopName}，預估 $etaText"
        val hourLabel = profile.preferredHour.toString().padStart(2, '0')
        val pathName = routeData.pathNames[nearestStop.pathId]
        val bigText = buildString {
            append("你通常會在 ")
            append(hourLabel)
            append(":00 左右查看這條路線。")
            if (!pathName.isNullOrBlank()) {
                append("方向：")
                append(pathName)
                append("。")
            }
            append("最近站牌：")
            append(nearestStop.stopName)
            append("（距離你約 ")
            append(formatDistance(distanceMeters))
            append("）。預估到站 ")
            append(etaText)
            append('。')
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_bus)
            .setContentTitle(title)
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .build()

        NotificationManagerCompat.from(context).notify(
            710000 + profile.routeKey,
            notification,
        )

        notificationPreferences(context)
            .edit()
            .putLong(
                LAST_NOTIFIED_KEY_PREFIX +
                    listOf(profile.provider, profile.routeKey, nearestStop.pathId, nearestStop.stopId)
                        .joinToString("_"),
                nowMs,
            ).apply()
    }

    fun canPostNotifications(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun scoreProfile(
        profile: SmartRouteProfile,
        currentHour: Int,
        previousHour: Int,
        nextHour: Int,
        nowMs: Long,
    ): Double {
        val currentOpenCount = profile.countAtHour(currentHour)
        val currentSelectionCount = profile.selectionCountAtHour(currentHour)
        val adjacentOpenCount =
            profile.countAtHour(previousHour) + profile.countAtHour(nextHour)
        val adjacentSelectionCount =
            profile.selectionCountAtHour(previousHour) +
                profile.selectionCountAtHour(nextHour)
        val preferredCount = profile.combinedCountAtHour(profile.preferredHour)
        val recencyDays = if (profile.latestInteractionAtMs <= 0L) {
            365.0
        } else {
            (nowMs - profile.latestInteractionAtMs).toDouble() / (24 * 60 * 60 * 1000)
        }
        val recencyBonus = when {
            recencyDays <= 2 -> 1.5
            recencyDays <= 7 -> 0.75
            else -> 0.0
        }
        return (currentOpenCount * 5) +
            (currentSelectionCount * 3.5) +
            (adjacentOpenCount * 2.5) +
            (adjacentSelectionCount * 1.5) +
            (preferredCount * 0.5) +
            (profile.totalOpens * 0.15) +
            (profile.totalSelections * 0.1) +
            recencyBonus
    }

    private fun hasEnoughHistoryForRecommendation(
        profile: SmartRouteProfile,
        currentHour: Int,
        previousHour: Int,
        nextHour: Int,
    ): Boolean {
        if (profile.totalOpens < MIN_TOTAL_OPENS_FOR_RECOMMENDATION) {
            return false
        }
        val relevantInteractions =
            profile.combinedCountAtHour(currentHour) +
                profile.combinedCountAtHour(previousHour) +
                profile.combinedCountAtHour(nextHour)
        return relevantInteractions >= MIN_RELEVANT_INTERACTIONS_FOR_RECOMMENDATION
    }

    private fun hasLocationPermission(context: Context): Boolean {
        val hasFine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackground = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasBackground) {
                return false
            }
        }
        return true
    }

    private fun resolveDatabaseFile(context: Context, provider: String): File? {
        val filesParent = context.filesDir.parentFile ?: return null
        val candidates = listOf(
            File(filesParent, "app_flutter/.yabus_backend/bus_${provider}_v2.sqlite"),
            File(context.filesDir, ".yabus_backend/bus_${provider}_v2.sqlite"),
            File(filesParent, "app_flutter/.taiwanbus/bus_${provider}.sqlite"),
            File(context.filesDir, ".taiwanbus/bus_${provider}.sqlite"),
        )
        return candidates.firstOrNull { it.exists() } ?: candidates.first()
    }

    private fun loadStopsFromDatabase(
        database: SQLiteDatabase,
        routeKey: Int,
    ): List<SmartRouteStop> {
        val result = mutableListOf<SmartRouteStop>()
        database.rawQuery(
            """
            SELECT path_id, stop_id, stop_name, sequence, lon, lat
            FROM stops
            WHERE route_key = ?
            ORDER BY path_id ASC, sequence ASC
            """.trimIndent(),
            arrayOf(routeKey.toString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result += SmartRouteStop(
                    pathId = cursor.getInt(0),
                    stopId = cursor.getInt(1),
                    stopName = cursor.getString(2).orEmpty(),
                    sequence = cursor.getInt(3),
                    lon = cursor.getDouble(4),
                    lat = cursor.getDouble(5),
                )
            }
        }
        return result
    }

    private fun parseLiveStopMap(
        jsonText: String,
        preferredPathId: Int,
    ): Map<Int, SmartLiveStop> {
        val root = JSONObject(jsonText)
        val paths = root.optJSONArray("paths") ?: return emptyMap()
        val result = mutableMapOf<Int, SmartLiveStop>()

        fun appendPath(pathObject: JSONObject) {
            val stops = pathObject.optJSONArray("stops") ?: return
            for (index in 0 until stops.length()) {
                val stop = stops.optJSONObject(index) ?: continue
                val stopId = parseStopId(stop.opt("stopid"))
                if (stopId <= 0) {
                    continue
                }
                result[stopId] = SmartLiveStop(
                    sec = toIntOrNull(stop.opt("eta")),
                    msg = stop.opt("message")
                        ?.toString()
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) },
                )
            }
        }

        var matchedPath = false
        for (index in 0 until paths.length()) {
            val pathObject = paths.optJSONObject(index) ?: continue
            if (toIntOrNull(pathObject.opt("pathid")) == preferredPathId) {
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

    private fun formatEtaText(liveStop: SmartLiveStop): String {
        val message = liveStop.msg?.trim().orEmpty()
        if (message.isNotEmpty()) {
            return message
        }
        val seconds = liveStop.sec ?: return "--"
        if (seconds <= 0) {
            return "進站中"
        }
        if (seconds < 60) {
            return "1 分內"
        }
        return "${seconds / 60} 分"
    }

    private fun formatDistance(distanceMeters: Double): String {
        if (distanceMeters < 1000) {
            return "${distanceMeters.toInt()}m"
        }
        val kilometers = distanceMeters / 1000.0
        return String.format("%.1fkm", kilometers)
    }

    private fun loadFlutterJsonObject(
        context: Context,
        primaryKey: String,
        fallbackKey: String,
    ): JSONObject? {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(primaryKey, null)
            ?: preferences.getString(fallbackKey, null)
            ?: return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun notificationPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(
            NOTIFICATION_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
    }
}

private data class SmartRouteSettings(
    val provider: String,
    val enableNotifications: Boolean,
)

private data class SmartRouteProfile(
    val provider: String,
    val routeKey: Int,
    val routeName: String,
    val totalOpens: Int,
    val lastOpenedAtMs: Long,
    val totalSelections: Int,
    val lastSelectedAtMs: Long,
    val hourlyOpens: Map<Int, Int>,
    val hourlySelections: Map<Int, Int>,
) {
    fun countAtHour(hour: Int): Int = hourlyOpens[hour] ?: 0
    fun selectionCountAtHour(hour: Int): Int = hourlySelections[hour] ?: 0
    fun combinedCountAtHour(hour: Int): Int = countAtHour(hour) + selectionCountAtHour(hour)

    val latestInteractionAtMs: Long
        get() = maxOf(lastOpenedAtMs, lastSelectedAtMs)

    val preferredHour: Int
        get() {
            var bestHour = 0
            var bestCount = -1
            for (hour in 0..23) {
                val count = combinedCountAtHour(hour)
                if (count > bestCount) {
                    bestHour = hour
                    bestCount = count
                }
            }
            return bestHour
        }
}

private data class SmartRouteData(
    val provider: String,
    val routeKey: Int,
    val routeId: String,
    val routeName: String,
    val pathNames: Map<Int, String>,
    val stops: List<SmartRouteStop>,
)

private data class SmartRouteStop(
    val pathId: Int,
    val stopId: Int,
    val stopName: String,
    val sequence: Int,
    val lon: Double,
    val lat: Double,
)

private data class SmartNearestStop(
    val pathId: Int,
    val stopId: Int,
    val stopName: String,
    val distanceMeters: Double,
)

private data class SmartLiveStop(
    val sec: Int?,
    val msg: String?,
)
