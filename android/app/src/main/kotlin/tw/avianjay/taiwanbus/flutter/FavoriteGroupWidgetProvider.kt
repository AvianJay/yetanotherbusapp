package tw.avianjay.taiwanbus.flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import java.io.File
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.util.Date
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

class FavoriteGroupWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        FavoriteWidgetRefreshScheduler.syncFromPreferences(context)
        FavoriteGroupWidgetSupport.updateWidgetsAsync(context, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != FavoriteGroupWidgetSupport.ACTION_REFRESH_WIDGET) {
            return
        }

        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return
        }

        val pendingResult = goAsync()
        FavoriteGroupWidgetSupport.updateWidgetsAsync(
            context = context,
            appWidgetIds = intArrayOf(appWidgetId),
            showLoading = true,
            pendingResult = pendingResult,
        )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { appWidgetId ->
            FavoriteGroupWidgetSupport.deleteConfiguredGroup(context, appWidgetId)
        }
        FavoriteWidgetRefreshScheduler.syncFromPreferences(context)
    }
}

object FavoriteGroupWidgetSupport {
    const val ACTION_REFRESH_WIDGET =
        "tw.avianjay.taiwanbus.flutter.action.REFRESH_FAVORITE_WIDGET"

    private const val WIDGET_PREFERENCES_NAME = "favorite_group_widget"
    private const val WIDGET_GROUP_KEY_PREFIX = "group_"
    private const val WIDGET_LAST_UPDATED_KEY_PREFIX = "last_updated_"
    private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val FAVORITE_GROUPS_KEY = "flutter.favorite_groups"
    private const val FAVORITE_GROUPS_FALLBACK_KEY = "favorite_groups"
    private const val MAX_WIDGET_ITEMS = 6
    private const val API_BASE_URL = "https://bus.avianjay.sbs"

    private val executor = Executors.newSingleThreadExecutor()

    fun saveConfiguredGroup(context: Context, appWidgetId: Int, groupName: String) {
        widgetPreferences(context)
            .edit()
            .putString(widgetGroupKey(appWidgetId), groupName)
            .apply()
    }

    fun loadConfiguredGroup(context: Context, appWidgetId: Int): String? {
        return widgetPreferences(context).getString(widgetGroupKey(appWidgetId), null)
    }

    fun deleteConfiguredGroup(context: Context, appWidgetId: Int) {
        widgetPreferences(context)
            .edit()
            .remove(widgetGroupKey(appWidgetId))
            .remove(widgetLastUpdatedKey(appWidgetId))
            .apply()
    }

    fun loadFavoriteGroupNames(context: Context): List<String> {
        return loadFavoriteGroups(context).keys.sorted()
    }

    fun requestRefreshAll(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, FavoriteGroupWidgetProvider::class.java),
        )
        if (appWidgetIds.isNotEmpty()) {
            updateWidgetsAsync(context, appWidgetIds, showLoading = true)
        }
    }

    fun updateWidgetsAsync(
        context: Context,
        appWidgetIds: IntArray,
        showLoading: Boolean = false,
        pendingResult: BroadcastReceiver.PendingResult? = null,
    ) {
        val appContext = context.applicationContext
        val appWidgetManager = AppWidgetManager.getInstance(appContext)
        if (showLoading) {
            appWidgetIds.forEach { appWidgetId ->
                appWidgetManager.updateAppWidget(
                    appWidgetId,
                    buildLoadingRemoteViews(appContext, appWidgetId),
                )
            }
        }

        executor.execute {
            try {
                updateWidgetsNow(appContext, appWidgetIds)
            } finally {
                pendingResult?.finish()
            }
        }
    }

    fun updateWidgetsNow(
        context: Context,
        appWidgetIds: IntArray,
    ) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        appWidgetIds.forEach { appWidgetId ->
            val renderResult = buildWidgetRenderResult(context, appWidgetId)
            if (renderResult.updateTimestamp) {
                val timestamp = System.currentTimeMillis()
                saveLastUpdated(context, appWidgetId, timestamp)
                renderResult.views.setTextViewText(
                    R.id.favorite_widget_updated_at,
                    formatLastUpdated(context, timestamp),
                )
            }
            appWidgetManager.updateAppWidget(
                appWidgetId,
                renderResult.views,
            )
        }
    }

    private fun buildWidgetRenderResult(
        context: Context,
        appWidgetId: Int,
    ): WidgetRenderResult {
        val groupName = loadConfiguredGroup(context, appWidgetId)
        return when {
            groupName.isNullOrBlank() -> {
                WidgetRenderResult(
                    views = buildBaseRemoteViews(context, appWidgetId, "YABus").apply {
                        setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
                        setTextViewText(R.id.favorite_widget_empty, "點一下設定這個小工具。")
                    },
                    updateTimestamp = false,
                )
            }

            else -> {
                val items = loadFavoriteGroups(context)[groupName]
                if (items == null) {
                    WidgetRenderResult(
                        views = buildBaseRemoteViews(context, appWidgetId, groupName).apply {
                            setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
                            setTextViewText(
                                R.id.favorite_widget_empty,
                                "這個最愛群組已不存在。",
                            )
                        },
                        updateTimestamp = false,
                    )
                } else {
                    buildContentRemoteViews(context, appWidgetId, groupName, items)
                }
            }
        }
    }

    private fun buildLoadingRemoteViews(context: Context, appWidgetId: Int): RemoteViews {
        val title = loadConfiguredGroup(context, appWidgetId) ?: "YABus"
        return buildBaseRemoteViews(context, appWidgetId, title).apply {
            setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
            setTextViewText(R.id.favorite_widget_empty, "更新中...")
        }
    }

    private fun buildContentRemoteViews(
        context: Context,
        appWidgetId: Int,
        groupName: String,
        items: List<FavoriteWidgetItem>,
    ): WidgetRenderResult {
        val views = buildBaseRemoteViews(context, appWidgetId, groupName)
        if (items.isEmpty()) {
            views.setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
            views.setTextViewText(R.id.favorite_widget_empty, "這個群組目前還沒有儲存站牌。")
            return WidgetRenderResult(views, updateTimestamp = true)
        }

        val liveStopsByRoute = linkedMapOf<String, Map<String, WidgetLiveStop>>()
        var successfulRouteFetches = 0
        items.associateBy(::routeRequestKey).forEach { (requestKey, item) ->
            val fetchResult = fetchLiveStopMap(context, item)
            if (fetchResult.success) {
                successfulRouteFetches += 1
            }
            liveStopsByRoute[requestKey] = fetchResult.liveStops
        }

        views.removeAllViews(R.id.favorite_widget_items_container)
        items.take(MAX_WIDGET_ITEMS).forEach { item ->
            val liveStop = liveStopsByRoute[routeRequestKey(item)]?.get("${item.pathId}:${item.stopId}")
            val itemViews = RemoteViews(context.packageName, R.layout.favorite_group_widget_item)
            itemViews.setTextViewText(
                R.id.favorite_widget_item_eta,
                formatEtaText(liveStop),
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_route,
                item.routeName.ifBlank { "路線 ${item.routeKey}" },
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_stop,
                item.stopName.ifBlank { "站牌 ${item.stopId}" },
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_note,
                liveStop?.vehicleId ?: "",
            )
            itemViews.setOnClickPendingIntent(
                R.id.favorite_widget_item_root,
                createRoutePendingIntent(context, item),
            )
            views.addView(R.id.favorite_widget_items_container, itemViews)
        }

        return WidgetRenderResult(
            views = views,
            updateTimestamp = successfulRouteFetches > 0,
        )
    }

    private fun buildBaseRemoteViews(
        context: Context,
        appWidgetId: Int,
        title: String,
    ): RemoteViews {
        return RemoteViews(context.packageName, R.layout.favorite_group_widget).apply {
            setTextViewText(R.id.favorite_widget_title, title)
            setTextViewText(
                R.id.favorite_widget_updated_at,
                formatLastUpdated(context, loadLastUpdated(context, appWidgetId)),
            )
            setOnClickPendingIntent(
                R.id.favorite_widget_header,
                createOpenFavoritesPendingIntent(context, appWidgetId, title),
            )
            setOnClickPendingIntent(
                R.id.favorite_widget_refresh,
                createRefreshPendingIntent(context, appWidgetId),
            )
            removeAllViews(R.id.favorite_widget_items_container)
            setViewVisibility(R.id.favorite_widget_empty, View.GONE)
        }
    }

    private fun createRefreshPendingIntent(
        context: Context,
        appWidgetId: Int,
    ): PendingIntent {
        val intent = Intent(context, FavoriteGroupWidgetProvider::class.java).apply {
            action = ACTION_REFRESH_WIDGET
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse("yabus://widget/$appWidgetId/refresh")
        }
        return PendingIntent.getBroadcast(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createOpenFavoritesPendingIntent(
        context: Context,
        appWidgetId: Int,
        groupName: String,
    ): PendingIntent {
        val intent = AppLaunchConstants.createFavoritesGroupIntent(context, groupName).apply {
            data = Uri.parse("yabus://widget/$appWidgetId/group/${Uri.encode(groupName)}")
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId * 17,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createRoutePendingIntent(
        context: Context,
        item: FavoriteWidgetItem,
    ): PendingIntent {
        val requestCode = (item.routeKey * 31) + item.stopId
        val intent = AppLaunchConstants.createRouteDetailIntent(
            context = context,
            provider = item.provider,
            routeKey = item.routeKey,
            pathId = item.pathId,
            stopId = item.stopId,
            destinationPathId = item.destinationPathId,
            destinationStopId = item.destinationStopId,
        ).apply {
            data = Uri.parse(
                "yabus://route/${item.provider}/${item.routeKey}/${item.pathId}/${item.stopId}",
            ).buildUpon()
                .apply {
                    item.destinationPathId?.let { appendQueryParameter("destinationPathId", it.toString()) }
                    item.destinationStopId?.let { appendQueryParameter("destinationStopId", it.toString()) }
                }
                .build()
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun loadFavoriteGroups(context: Context): Map<String, List<FavoriteWidgetItem>> {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(FAVORITE_GROUPS_KEY, null)
            ?: preferences.getString(FAVORITE_GROUPS_FALLBACK_KEY, null)
            ?: return emptyMap()
        val root = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return emptyMap()
        }

        val result = linkedMapOf<String, List<FavoriteWidgetItem>>()
        root.keys().forEach { groupName ->
            val groupItems = mutableListOf<FavoriteWidgetItem>()
            val groupArray = root.optJSONArray(groupName) ?: JSONArray()
            for (index in 0 until groupArray.length()) {
                val item = groupArray.optJSONObject(index) ?: continue
                val routeKey = item.optInt("routeKey", 0)
                val stopId = item.optInt("stopId", 0)
                if (routeKey <= 0 || stopId <= 0) {
                    continue
                }
                val destinationStopId = item.optInt("destinationStopId", 0)
                    .takeIf { it > 0 }
                val destinationPathId = if (destinationStopId == null) {
                    null
                } else {
                    item.optInt("destinationPathId", item.optInt("pathId", 0))
                }
                groupItems += FavoriteWidgetItem(
                    provider = item.optString("provider", "twn"),
                    routeKey = routeKey,
                    pathId = item.optInt("pathId", 0),
                    stopId = stopId,
                    routeId = item.optString("routeId", "")
                        .trim()
                        .takeIf { it.isNotEmpty() },
                    routeName = item.optString("routeName", ""),
                    stopName = item.optString("stopName", ""),
                    destinationPathId = destinationPathId,
                    destinationStopId = destinationStopId,
                    destinationStopName = item.optString("destinationStopName", "")
                        .trim()
                        .takeIf { it.isNotEmpty() },
                )
            }
            result[groupName] = groupItems
        }
        return result
    }

    private fun fetchLiveStopMap(
        context: Context,
        item: FavoriteWidgetItem,
    ): WidgetRouteFetchResult {
        val routeId = resolveRouteId(context, item)
            ?: return WidgetRouteFetchResult(success = false, liveStops = emptyMap())
        val encodedRouteId = URLEncoder.encode(routeId, Charsets.UTF_8.name())
        val connection = URL("$API_BASE_URL/api/v1/routes/$encodedRouteId/realtime")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", NativeApiUserAgent.value())
        connection.doInput = true
        connection.useCaches = false

        return try {
            if (connection.responseCode !in 200..299) {
                return WidgetRouteFetchResult(success = false, liveStops = emptyMap())
            }
            val jsonText = connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                reader.readText()
            }
            WidgetRouteFetchResult(
                success = true,
                liveStops = parseLiveStopMap(jsonText, item.pathId),
            )
        } catch (_: Exception) {
            WidgetRouteFetchResult(success = false, liveStops = emptyMap())
        } finally {
            connection.disconnect()
        }
    }

    private fun resolveRouteId(
        context: Context,
        item: FavoriteWidgetItem,
    ): String? {
        val explicitRouteId = item.routeId?.trim()
        if (!explicitRouteId.isNullOrEmpty()) {
            return explicitRouteId
        }
        return queryRouteIdFromDatabase(context, item.provider, item.routeKey)
    }

    private fun queryRouteIdFromDatabase(
        context: Context,
        provider: String,
        routeKey: Int,
    ): String? {
        val databaseFile = resolveDatabaseFile(context, provider) ?: return null
        if (!databaseFile.exists()) {
            return null
        }

        val database = try {
            SQLiteDatabase.openDatabase(
                databaseFile.path,
                null,
                SQLiteDatabase.OPEN_READONLY,
            )
        } catch (_: Exception) {
            return null
        }

        return try {
            database.rawQuery(
                "SELECT route_id FROM routes WHERE route_key = ? LIMIT 1",
                arrayOf(routeKey.toString()),
            ).use { cursor ->
                if (!cursor.moveToFirst()) {
                    null
                } else {
                    cursor.getString(0)
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() }
                }
            }
        } finally {
            database.close()
        }
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

    private fun parseLiveStopMap(
        jsonText: String,
        preferredPathId: Int,
    ): Map<String, WidgetLiveStop> {
        val root = JSONObject(jsonText)
        val paths = root.optJSONArray("paths") ?: return emptyMap()
        val result = mutableMapOf<String, WidgetLiveStop>()

        fun appendPath(pathObject: JSONObject) {
            val pathId = toIntOrNull(pathObject.opt("pathid")) ?: return
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
                result["$pathId:$stopId"] = WidgetLiveStop(
                    sec = toIntOrNull(stopObject.opt("eta")),
                    msg = message,
                    vehicleId = firstVehicleId(stopObject.optJSONArray("buses")),
                )
            }
        }

        for (index in 0 until paths.length()) {
            val pathObject = paths.optJSONObject(index) ?: continue
            appendPath(pathObject)
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

    private fun firstVehicleId(buses: JSONArray?): String? {
        if (buses == null) {
            return null
        }
        for (index in 0 until buses.length()) {
            val busObject = buses.optJSONObject(index) ?: continue
            val vehicleId = busObject.opt("id")
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
                    ?.takeIf { it.isNotEmpty() }
            if (vehicleId != null) {
                return vehicleId
            }
        }
        return null
    }

    private fun formatEtaText(liveStop: WidgetLiveStop?): String {
        liveStop ?: return "--"
        val message = liveStop.msg?.trim().orEmpty()
        if (message.isNotEmpty()) {
            return message
        }
        val seconds = liveStop.sec ?: return "--"
        if (seconds <= 0) {
            return "進站中"
        }
        if (seconds < 60) {
            return "即將進站"
        }
        return "${seconds / 60}分"
    }

    private fun formatLastUpdated(
        context: Context,
        timestamp: Long?,
    ): String {
        if (timestamp == null) {
            return "上次更新 --"
        }
        val formatter = DateFormat.getTimeFormat(context)
        return "上次更新 ${formatter.format(Date(timestamp))}"
    }

    private fun routeRequestKey(item: FavoriteWidgetItem): String {
        return item.routeId?.takeIf { it.isNotBlank() }
            ?: "${item.provider}:${item.routeKey}"
    }

    private fun saveLastUpdated(context: Context, appWidgetId: Int, timestamp: Long) {
        widgetPreferences(context)
            .edit()
            .putLong(widgetLastUpdatedKey(appWidgetId), timestamp)
            .apply()
    }

    private fun loadLastUpdated(context: Context, appWidgetId: Int): Long? {
        val preferences = widgetPreferences(context)
        if (!preferences.contains(widgetLastUpdatedKey(appWidgetId))) {
            return null
        }
        return preferences.getLong(widgetLastUpdatedKey(appWidgetId), 0L)
    }

    private fun widgetPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(WIDGET_PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    private fun widgetGroupKey(appWidgetId: Int): String {
        return "$WIDGET_GROUP_KEY_PREFIX$appWidgetId"
    }

    private fun widgetLastUpdatedKey(appWidgetId: Int): String {
        return "$WIDGET_LAST_UPDATED_KEY_PREFIX$appWidgetId"
    }
}

data class FavoriteWidgetItem(
    val provider: String,
    val routeKey: Int,
    val pathId: Int,
    val stopId: Int,
    val routeId: String?,
    val routeName: String,
    val stopName: String,
    val destinationPathId: Int?,
    val destinationStopId: Int?,
    val destinationStopName: String?,
)

data class WidgetLiveStop(
    val sec: Int?,
    val msg: String?,
    val vehicleId: String?,
)

data class WidgetRouteFetchResult(
    val success: Boolean,
    val liveStops: Map<String, WidgetLiveStop>,
)

data class WidgetRenderResult(
    val views: RemoteViews,
    val updateTimestamp: Boolean,
)
