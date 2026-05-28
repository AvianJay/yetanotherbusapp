package tw.avianjay.taiwanbus.wearos.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import tw.avianjay.taiwanbus.wearos.BuildConfig
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Lightweight nearby-stops loader.
 *
 * The phone app already exposes `/api/v1/cities/{city}/stops/nearby`; we reuse
 * that endpoint and group results by stop. The city is inferred from either
 * the synced favourites or the persisted usage profiles, falling back to
 * Taipei when neither is available.
 */
object WearNearbyService {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchNearby(
        context: Context,
        radiusMeters: Int = 500,
        limit: Int = 24,
    ): List<WearNearbyStop> = withContext(Dispatchers.IO) {
        val granted = hasLocationPermission(context)
        if (!granted) {
            throw SecurityException("需要位置權限")
        }
        val location = requestCurrentLocation(context)
            ?: throw IllegalStateException("無法取得目前位置")

        val provider = inferProvider(WearDataRepository.state)
        val city = cityForProvider(provider)
        val payload = requestJson(
            "${BuildConfig.WEAR_API_BASE_URL}/api/v1/cities/${encodePath(city)}/stops/nearby" +
                "?lat=${location.first}&lon=${location.second}&radius=$radiusMeters&limit=$limit",
        )
        val array = (payload as? JsonArray) ?: return@withContext emptyList()

        val grouped = LinkedHashMap<Int, WearNearbyStop>()
        for (item in array) {
            val row = item as? JsonObject ?: continue
            val stopId = parseStopId(row["stopid"])
            val stopName = row.string("stop_name").ifBlank { continue }
            val routeId = row.string("routeid").ifBlank { continue }
            val pathId = row.int("pathid") ?: 0
            val pathName = row.string("path_name")
            val routeName = row.string("route_name").ifBlank { routeId }
            val distance = (row["distance"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: 0.0

            val route = WearNearbyRoute(
                routeId = routeId,
                routeName = routeName,
                pathId = pathId,
                pathName = pathName,
                etaText = "點擊查看",
                etaSeconds = null,
            )

            val existing = grouped[stopId]
            if (existing == null) {
                grouped[stopId] = WearNearbyStop(
                    stopId = stopId,
                    stopName = stopName,
                    provider = provider,
                    distanceMeters = distance,
                    routes = listOf(route),
                )
            } else if (existing.routes.none { it.routeId == routeId && it.pathId == pathId }) {
                grouped[stopId] = existing.copy(routes = existing.routes + route)
            }
        }
        grouped.values.sortedBy { it.distanceMeters }
    }

    fun hasLocationPermission(context: Context): Boolean {
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
        return coarse == PackageManager.PERMISSION_GRANTED ||
            fine == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private suspend fun requestCurrentLocation(context: Context): Pair<Double, Double>? {
        val client = LocationServices.getFusedLocationProviderClient(context.applicationContext)
        return suspendCancellableCoroutine { continuation ->
            val tokenSource = CancellationTokenSource()
            continuation.invokeOnCancellation { tokenSource.cancel() }
            client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, tokenSource.token)
                .addOnSuccessListener { location ->
                    if (location == null) {
                        continuation.resume(null)
                    } else {
                        continuation.resume(location.latitude to location.longitude)
                    }
                }
                .addOnFailureListener { error ->
                    continuation.resumeWithException(error)
                }
        }
    }

    private fun inferProvider(state: WearHomeState): String {
        return state.favorites.firstOrNull()?.provider
            ?: state.usageProfiles.firstOrNull()?.provider
            ?: "tpe"
    }

    private fun cityForProvider(provider: String): String = when (provider.lowercase()) {
        "kee" -> "Keelung"
        "tpe" -> "Taipei"
        "nwt" -> "NewTaipei"
        "tao" -> "Taoyuan"
        "hsz" -> "Hsinchu"
        "hsq" -> "HsinchuCounty"
        "mia" -> "MiaoliCounty"
        "txg" -> "Taichung"
        "cha" -> "ChanghuaCounty"
        "nan" -> "NantouCounty"
        "yun" -> "YunlinCounty"
        "cyi" -> "Chiayi"
        "cyq" -> "ChiayiCounty"
        "tnn" -> "Tainan"
        "khh" -> "Kaohsiung"
        "pif" -> "PingtungCounty"
        "ila" -> "YilanCounty"
        "hua" -> "HualienCounty"
        "ttt" -> "TaitungCounty"
        "pen" -> "PenghuCounty"
        "kin" -> "KinmenCounty"
        "lie" -> "LienchiangCounty"
        else -> "Taipei"
    }

    private fun requestJson(url: String): kotlinx.serialization.json.JsonElement {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "YABus-Wear/1.0")
        }
        return try {
            val status = connection.responseCode
            val stream = if (status in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream ?: connection.inputStream
            }
            val body = stream.bufferedReader(StandardCharsets.UTF_8).use(BufferedReader::readText)
            if (status != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("Nearby API failed ($status).")
            }
            json.parseToJsonElement(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun JsonObject.string(key: String): String =
        (this[key] as? JsonPrimitive)?.content?.trim().orEmpty()

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.content?.toIntOrNull()

    private fun parseStopId(raw: kotlinx.serialization.json.JsonElement?): Int {
        val text = (raw as? JsonPrimitive)?.content?.trim().orEmpty()
        return text.toIntOrNull() ?: text.hashCode() and 0x7fffffff
    }

    private fun encodePath(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
}
