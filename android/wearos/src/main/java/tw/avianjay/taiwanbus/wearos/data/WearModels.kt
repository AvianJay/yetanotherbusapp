package tw.avianjay.taiwanbus.wearos.data

import kotlinx.serialization.Serializable

@Serializable
data class WearSettings(
    val syncEnabled: Boolean = false,
    val selectedFavoriteIds: List<String> = emptyList(),
    val lastUpdatedAtMs: Long = 0L,
)

@Serializable
data class FavoriteStop(
    val id: String,
    val groupName: String = "",
    val provider: String = "",
    val routeKey: Int = 0,
    val pathId: Int = 0,
    val stopId: Int = 0,
    val routeId: String? = null,
    val routeName: String? = null,
    val stopName: String? = null,
    val destinationPathId: Int? = null,
    val destinationStopId: Int? = null,
    val destinationStopName: String? = null,
) {
    val displayRouteName: String
        get() = routeName?.takeIf { it.isNotBlank() } ?: routeKey.toString()

    val displayStopName: String
        get() = stopName?.takeIf { it.isNotBlank() } ?: "Stop $stopId"

    val realtimeRouteId: String?
        get() = routeId?.trim()?.takeIf { it.isNotEmpty() }
}

@Serializable
data class FavoritePayload(
    val favorites: List<FavoriteStop> = emptyList(),
    val lastUpdatedAtMs: Long = 0L,
)

@Serializable
data class BusArrival(
    val favoriteId: String,
    val etaText: String,
    val statusText: String,
    val arrivalEpochMs: Long? = null,
    val updatedAtMs: Long = 0L,
)

data class WearHomeState(
    val settings: WearSettings = WearSettings(),
    val favorites: List<FavoriteStop> = emptyList(),
    val arrivals: List<BusArrival> = emptyList(),
    val lastSyncedAtMs: Long? = null,
    val lastRefreshAtMs: Long? = null,
    val isRefreshing: Boolean = false,
    val lastRefreshError: String? = null,
    val smartSuggestion: WearSmartSuggestionPayload? = null,
    val usageProfiles: List<WearRouteUsageProfile> = emptyList(),
) {
    val hasSyncedFavorites: Boolean
        get() = settings.syncEnabled && favorites.isNotEmpty()

    fun arrivalFor(favoriteId: String): BusArrival? =
        arrivals.firstOrNull { it.favoriteId == favoriteId }
}

data class RouteSearchResult(
    val routeId: String,
    val routeName: String,
    val description: String,
    val provider: String,
)

@Serializable
data class WearRouteDetail(
    val routeId: String,
    val routeName: String,
    val provider: String,
    val paths: List<WearRoutePath> = emptyList(),
)

@Serializable
data class WearRoutePath(
    val pathId: Int,
    val name: String,
    val stops: List<WearRouteStop> = emptyList(),
)

@Serializable
data class WearRouteStop(
    val stopId: Int,
    val name: String,
    val sequence: Int,
    val etaText: String,
    val statusText: String,
)

/**
 * Smart route suggestion pushed from the phone. The watch may also synthesize
 * a fallback suggestion locally when [WearSmartRouteService] is used.
 */
@Serializable
data class WearSmartSuggestionPayload(
    val routeId: String,
    val routeName: String,
    val provider: String,
    val pathId: Int = 0,
    val pathName: String = "",
    val stopId: Int = 0,
    val stopName: String = "",
    val reason: String = "",
    val etaText: String? = null,
    val etaSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val source: String = "phone", // "phone" | "local"
    val generatedAtMs: Long = 0L,
)

/**
 * Compact slice of [RouteUsageProfile] enough for [WearSmartRouteService] to
 * score routes by time-of-day even when the phone is offline.
 */
@Serializable
data class WearRouteUsageProfile(
    val provider: String,
    val routeKey: Int,
    val routeId: String = "",
    val routeName: String = "",
    val totalOpens: Int = 0,
    val lastOpenedAtMs: Long = 0L,
    val hourlyOpens: Map<Int, Int> = emptyMap(),
    val recentSelectionMs: List<Long> = emptyList(),
)

@Serializable
data class WearUsageProfilePayload(
    val profiles: List<WearRouteUsageProfile> = emptyList(),
    val lastUpdatedAtMs: Long = 0L,
)

/**
 * Pre-rendered snapshot consumed by both [tile.YaBusTileService] and
 * [complication.NextBusComplicationService]. Persisted in SharedPreferences
 * so background services can read it synchronously.
 */
@Serializable
data class WearTileSnapshot(
    val suggestion: WearSmartSuggestionPayload? = null,
    val favorites: List<WearArrivalCard> = emptyList(),
    val lastUpdatedAtMs: Long = 0L,
    val syncEnabled: Boolean = false,
)

@Serializable
data class WearArrivalCard(
    val favoriteId: String,
    val routeName: String,
    val stopName: String,
    val etaText: String,
    val etaSeconds: Int? = null,
    val statusText: String = "",
    val routeId: String = "",
    val provider: String = "",
    val pathId: Int = 0,
    val stopId: Int = 0,
)

/**
 * Compact nearby stop entry used by the watch nearby screen.
 */
@Serializable
data class WearNearbyStop(
    val stopId: Int,
    val stopName: String,
    val provider: String,
    val distanceMeters: Double,
    val routes: List<WearNearbyRoute> = emptyList(),
)

@Serializable
data class WearNearbyRoute(
    val routeId: String,
    val routeName: String,
    val pathId: Int,
    val pathName: String,
    val etaText: String,
    val etaSeconds: Int? = null,
)

@Serializable
data class WearAddFavoriteRequest(
    val provider: String,
    val routeKey: Int,
    val routeId: String,
    val routeName: String,
    val pathId: Int,
    val pathName: String,
    val stopId: Int,
    val stopName: String,
    val requestedAtMs: Long,
)

