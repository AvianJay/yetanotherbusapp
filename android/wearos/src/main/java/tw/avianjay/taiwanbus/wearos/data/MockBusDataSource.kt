package tw.avianjay.taiwanbus.wearos.data

interface BusDataSource {
    fun buildArrivals(
        favorites: List<FavoriteStop>,
        updatedAtMs: Long,
    ): List<BusArrival>

    fun searchRoutes(query: String): List<RouteSearchResult>
}

object MockBusDataSource : BusDataSource {
    private val routes = listOf(
        RouteSearchResult("307", "Banqiao to Songshan", "NWT"),
        RouteSearchResult("605", "Zhonghe to Taipei Main", "TPE"),
        RouteSearchResult("R26", "Shilin to Yangmingshan", "TPE"),
        RouteSearchResult("965", "Xizhi to Banqiao", "NWT"),
        RouteSearchResult("299", "Yonghe to Songshan Airport", "TPE"),
        RouteSearchResult("Brown 7", "Taipei Zoo to Muzha", "TPE"),
        RouteSearchResult("9023", "Taipei to Taoyuan Airport", "INT"),
        RouteSearchResult("Blue 15", "Sanchong to Banqiao", "NWT"),
    )

    override fun buildArrivals(
        favorites: List<FavoriteStop>,
        updatedAtMs: Long,
    ): List<BusArrival> {
        return favorites.mapIndexed { index, favorite ->
            val minuteOffset = (
                favorite.routeKey +
                    favorite.stopId +
                    index +
                    (updatedAtMs / 60000L).toInt()
                ) % 11 + 1
            val arrivalAtMs = updatedAtMs + minuteOffset * 60_000L
            val etaText = when {
                minuteOffset <= 1 -> "Arriving"
                minuteOffset <= 2 -> "1 min"
                else -> "$minuteOffset min"
            }
            val statusText = when {
                minuteOffset <= 2 -> "Mock near stop"
                minuteOffset <= 5 -> "Mock on the way"
                else -> "Mock scheduled"
            }
            BusArrival(
                favoriteId = favorite.id,
                etaText = etaText,
                statusText = statusText,
                arrivalEpochMs = arrivalAtMs,
                updatedAtMs = updatedAtMs,
            )
        }
    }

    override fun searchRoutes(query: String): List<RouteSearchResult> {
        val normalized = query.trim().lowercase()
        if (normalized.isEmpty()) {
            return routes.take(6)
        }

        return routes.filter { route ->
            route.routeName.lowercase().contains(normalized) ||
                route.description.lowercase().contains(normalized) ||
                route.provider.lowercase().contains(normalized)
        }.take(8)
    }
}
