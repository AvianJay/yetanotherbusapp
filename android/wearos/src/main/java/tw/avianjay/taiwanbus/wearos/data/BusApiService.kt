package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import com.google.android.gms.common.GooglePlayServicesNotAvailableException
import com.google.android.gms.common.GooglePlayServicesRepairableException
import com.google.android.gms.security.ProviderInstaller
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import tw.avianjay.taiwanbus.wearos.BuildConfig
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import javax.net.ssl.SSLException
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException

object BusApiService {
    private val json = Json { ignoreUnknownKeys = true }
    private val timeFormatter = SimpleDateFormat("HH:mm", Locale.getDefault())
    @Volatile
    private var securityProviderPrepared = false

    suspend fun fetchArrivals(
        context: Context?,
        favorites: List<FavoriteStop>,
    ): List<BusArrival> =
        withContext(Dispatchers.IO) {
            ensureSecurityProvider(context)
            val routableFavorites = favorites.filter { it.realtimeRouteId != null }
            if (routableFavorites.isEmpty()) {
                return@withContext emptyList()
            }

            val requestedAtMs = System.currentTimeMillis()
            val routeIds = routableFavorites
                .mapNotNull { it.realtimeRouteId }
                .distinct()
            val routes = linkedMapOf<String, JsonObject>()

            routeIds.chunked(25).forEach { chunk ->
                val encodedRouteIds = chunk.joinToString(",") { encodePathSegment(it) }
                val payload = requestJson(
                    "${BuildConfig.WEAR_API_BASE_URL}/api/v1/batchroutes/$encodedRouteIds/realtime",
                ).jsonObject
                val chunkRoutes = payload["routes"]?.jsonObject ?: JsonObject(emptyMap())
                for ((routeId, routePayload) in chunkRoutes) {
                    val routeObject = routePayload as? JsonObject ?: continue
                    routes[routeId] = routeObject
                }
            }

            return@withContext routableFavorites.map { favorite ->
                val route = favorite.realtimeRouteId?.let(routes::get)
                val stop = route
                    ?.paths()
                    ?.firstOrNull { path ->
                        path.int("pathid") == favorite.pathId
                    }
                    ?.stops()
                    ?.firstOrNull { stopObject ->
                        parseStopId(stopObject["stopid"]) == favorite.stopId
                    }

                stop?.toArrival(
                    favoriteId = favorite.id,
                    requestedAtMs = requestedAtMs,
                    fallbackStatus = favorite.groupName.ifBlank { favorite.provider },
                ) ?: BusArrival(
                    favoriteId = favorite.id,
                    etaText = "No data",
                    statusText = "Realtime unavailable",
                    updatedAtMs = requestedAtMs,
                )
            }
        }

    suspend fun searchRoutes(
        context: Context?,
        query: String,
        limit: Int = 20,
    ): List<RouteSearchResult> = withContext(Dispatchers.IO) {
        ensureSecurityProvider(context)
        val normalized = query.trim()
        if (normalized.isEmpty()) {
            return@withContext emptyList()
        }

        val payload = requestJson(
            "${BuildConfig.WEAR_API_BASE_URL}/api/v1/routes?query=${encodeQueryValue(normalized)}&limit=$limit",
        ).jsonArray
        val grouped = LinkedHashMap<String, MutableRouteSearchResult>()
        for (item in payload) {
            val row = item.jsonObject
            val routeId = row.string("routeid")
            if (routeId.isBlank()) {
                continue
            }

            val routeName = row.string("route_name").ifBlank { routeId }
            val pathName = row.string("path_name")
            val provider = row.string("provider").ifBlank {
                routeId.substringBefore('_', missingDelimiterValue = routeId)
            }
            val bucket = grouped.getOrPut(routeId) {
                MutableRouteSearchResult(
                    routeId = routeId,
                    routeName = routeName,
                    provider = provider,
                )
            }
            if (pathName.isNotBlank()) {
                bucket.descriptions.add(pathName)
            }
        }

        return@withContext grouped.values.map { item ->
            RouteSearchResult(
                routeId = item.routeId,
                routeName = item.routeName,
                description = item.descriptions.joinToString(" / ").ifBlank { item.routeId },
                provider = item.provider,
            )
        }
    }

    suspend fun fetchRouteDetail(
        context: Context?,
        routeId: String,
        provider: String,
    ): WearRouteDetail = withContext(Dispatchers.IO) {
        ensureSecurityProvider(context)
        
        // 1. Fetch static stops metadata
        val stopsPayload = runCatching {
            requestJson(
                "${BuildConfig.WEAR_API_BASE_URL}/api/v1/routes/${encodePathSegment(routeId)}/stops",
            ).jsonObject
        }.getOrNull() ?: throw IllegalStateException("無法取得路線站牌資訊")

        // 2. Fetch real-time eta data (defensively fallback if fails)
        val realtimePayload = runCatching {
            requestJson(
                "${BuildConfig.WEAR_API_BASE_URL}/api/v1/routes/${encodePathSegment(routeId)}/realtime",
            ).jsonObject
        }.getOrNull()

        val routeName = stopsPayload.string("name").ifBlank { routeId }
        val requestedAtMs = System.currentTimeMillis()

        // 3. Map real-time stops by composite key for easy merging
        val realtimeStopsMap = mutableMapOf<String, JsonObject>()
        if (realtimePayload != null) {
            for (pathObj in realtimePayload.paths()) {
                val pathId = pathObj.int("pathid") ?: 0
                for (stopObj in pathObj.stops()) {
                    val stopId = parseStopId(stopObj["stopid"])
                    realtimeStopsMap["$pathId:$stopId"] = stopObj
                }
            }
        }

        // 4. Build paths and stops from the static stops metadata and merge real-time info
        val paths = stopsPayload.paths().map { pathObj ->
            val pathId = pathObj.int("pathid") ?: 0
            val pathName = pathObj.string("name").ifBlank {
                val dest = pathObj.string("destination")
                if (dest.isNotBlank()) "往 $dest" else "方向 $pathId"
            }
            
            val stops = pathObj.stops().map { stopObj ->
                val stopId = parseStopId(stopObj["stopid"])
                val stopName = stopObj.string("name")
                val seq = stopObj.int("seq") ?: 0

                val rtStop = realtimeStopsMap["$pathId:$stopId"]
                val etaSeconds = rtStop?.int("eta")
                val message = rtStop?.string("message").orEmpty()
                val updatedAtMs = rtStop?.let { parseUpdatedAt(it.string("updated_at")) } ?: requestedAtMs
                val busCount = (rtStop?.get("buses") as? JsonArray)?.size ?: 0

                val etaText = when {
                    message.isNotBlank() -> message
                    etaSeconds == null -> "--"
                    etaSeconds <= 0 -> "即將到站"
                    etaSeconds < 60 -> "${etaSeconds}秒"
                    else -> "${etaSeconds / 60}分"
                }

                val statusText = when {
                    busCount > 0 -> {
                        val label = if (busCount == 1) "1車" else "${busCount}車"
                        "$label | ${timeFormatter.format(Date(updatedAtMs))}"
                    }
                    rtStop != null && updatedAtMs > 0L -> "更新於 ${timeFormatter.format(Date(updatedAtMs))}"
                    else -> ""
                }

                WearRouteStop(
                    stopId = stopId,
                    name = stopName,
                    sequence = seq,
                    etaText = etaText,
                    statusText = statusText,
                )
            }

            WearRoutePath(
                pathId = pathId,
                name = pathName,
                stops = stops,
            )
        }

        WearRouteDetail(
            routeId = routeId,
            routeName = routeName,
            provider = provider,
            paths = paths,
        )
    }

    private fun requestJson(url: String): JsonElement {
        try {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "YABus-Wear/1.0")
            }

            return connection.use {
                val status = connection.responseCode
                val stream = if (status in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream ?: connection.inputStream
                }
                val body = stream.bufferedReader(StandardCharsets.UTF_8).use(BufferedReader::readText)
                if (status != HttpURLConnection.HTTP_OK) {
                    throw IllegalStateException("API request failed ($status).")
                }
                json.parseToJsonElement(body)
            }
        } catch (error: Throwable) {
            throw mapNetworkError(error)
        }
    }

    private fun ensureSecurityProvider(context: Context?) {
        if (context == null) {
            return
        }
        if (securityProviderPrepared) {
            return
        }

        synchronized(this) {
            if (securityProviderPrepared) {
                return
            }

            try {
                ProviderInstaller.installIfNeeded(context.applicationContext)
            } catch (_: Throwable) {
                // Ignored
            }

            securityProviderPrepared = true
        }
    }

    private fun JsonObject.paths(): List<JsonObject> =
        (this["paths"] as? JsonArray)
            ?.mapNotNull { it as? JsonObject }
            ?: emptyList()

    private fun JsonObject.stops(): List<JsonObject> =
        (this["stops"] as? JsonArray)
            ?.mapNotNull { it as? JsonObject }
            ?: emptyList()

    private fun JsonObject.string(key: String): String =
        (this[key] as? JsonPrimitive)?.content?.trim().orEmpty()

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.content?.toIntOrNull()

    private fun JsonObject.toArrival(
        favoriteId: String,
        requestedAtMs: Long,
        fallbackStatus: String,
    ): BusArrival {
        val etaSeconds = int("eta")
        val message = string("message")
        val updatedAtMs = parseUpdatedAt(string("updated_at")) ?: requestedAtMs
        val busCount = (this["buses"] as? JsonArray)?.size ?: 0
        val arrivalAtMs = etaSeconds
            ?.takeIf { it >= 0 }
            ?.let { requestedAtMs + it * 1000L }
        val etaText = when {
            message.isNotBlank() -> message
            etaSeconds == null -> "--"
            etaSeconds <= 0 -> "即將到站"
            etaSeconds < 60 -> "${etaSeconds}秒"
            else -> "${etaSeconds / 60} 分"
        }
        val statusText = when {
            busCount > 0 -> {
                val label = if (busCount == 1) "1 車" else "$busCount 車"
                "$label | ${timeFormatter.format(Date(updatedAtMs))}"
            }

            updatedAtMs > 0L -> "更新於 ${timeFormatter.format(Date(updatedAtMs))}"
            else -> fallbackStatus
        }
        return BusArrival(
            favoriteId = favoriteId,
            etaText = etaText,
            statusText = statusText,
            arrivalEpochMs = arrivalAtMs,
            updatedAtMs = updatedAtMs,
        )
    }

    private fun parseUpdatedAt(value: String): Long? {
        if (value.isBlank()) {
            return null
        }

        return runCatching {
            java.time.OffsetDateTime.parse(value).toInstant().toEpochMilli()
        }.getOrNull()
    }

    private fun parseStopId(raw: JsonElement?): Int {
        val text = (raw as? JsonPrimitive)?.content?.trim().orEmpty()
        val parsed = text.toIntOrNull()
        if (parsed != null) {
            return parsed
        }

        var hash = 0
        for (codeUnit in text) {
            hash = (hash * 31 + codeUnit.code) and 0x7fffffff
        }
        return hash
    }

    private fun encodePathSegment(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private fun encodeQueryValue(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    private inline fun <T> HttpURLConnection.use(block: () -> T): T {
        return try {
            block()
        } finally {
            disconnect()
        }
    }

    private fun mapNetworkError(error: Throwable): Throwable {
        if (error is IllegalStateException) {
            return error
        }

        return if (error.isCertificateChainError()) {
            IllegalStateException(
                "Secure connection failed on this watch. Check Google Play services and the watch date/time.",
                error,
            )
        } else {
            error
        }
    }

    private fun Throwable.isCertificateChainError(): Boolean {
        if (this is SSLHandshakeException || this is SSLPeerUnverifiedException || this is SSLException) {
            val message = message.orEmpty().lowercase(Locale.US)
            if ("chain validation failed" in message || "trust anchor" in message || "certificate" in message) {
                return true
            }
        }

        val cause = cause ?: return false
        return cause !== this && cause.isCertificateChainError()
    }
}

private data class MutableRouteSearchResult(
    val routeId: String,
    val routeName: String,
    val provider: String,
    val descriptions: LinkedHashSet<String> = linkedSetOf(),
)
