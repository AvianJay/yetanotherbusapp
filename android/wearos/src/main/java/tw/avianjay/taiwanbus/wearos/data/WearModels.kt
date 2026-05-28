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

