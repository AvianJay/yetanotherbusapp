package tw.avianjay.taiwanbus.wearos.data

object WearSyncPaths {
    // Phone -> Watch (DataClient)
    const val pathSettings = "/wear/settings"
    const val pathFavorites = "/wear/favorites"
    const val pathSmartSuggestion = "/wear/smart_suggestion"
    const val pathUsageProfiles = "/wear/usage_profiles"

    // Phone -> Watch (MessageClient)
    const val pathRefresh = "/wear/refresh"
    const val pathCancelRefresh = "/wear/cancel_refresh"

    // Watch -> Phone (MessageClient)
    const val pathAddFavorite = "/wear/add_favorite"
    const val pathOpenRoute = "/wear/open_route"

    const val keyPayloadJson = "payload_json"
}
