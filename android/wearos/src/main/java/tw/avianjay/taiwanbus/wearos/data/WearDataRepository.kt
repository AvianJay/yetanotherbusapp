package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

object WearDataRepository {
    private const val preferencesName = "wear_sync_state"
    private const val keySettingsJson = "settings_json"
    private const val keyFavoritesJson = "favorites_json"
    private const val keyArrivalsJson = "arrivals_json"
    private const val keyLastRefreshAtMs = "last_refresh_at_ms"
    private const val keySmartSuggestionJson = "smart_suggestion_json"
    private const val keyUsageProfilesJson = "usage_profiles_json"
    private const val keyTileSnapshotJson = "tile_snapshot_json"

    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var refreshJob: Job? = null
    private var loaded = false

    /** Callbacks invoked whenever any data backing Tiles / Complications changes. */
    private val snapshotListeners = mutableListOf<(Context) -> Unit>()

    fun registerSnapshotListener(listener: (Context) -> Unit) {
        snapshotListeners.add(listener)
    }

    var state by mutableStateOf(WearHomeState())
        private set

    fun ensureLoaded(context: Context) {
        if (loaded) {
            return
        }
        loaded = true

        val preferences = preferences(context)
        val settings = decode<WearSettings>(
            preferences.getString(keySettingsJson, null),
        ) ?: WearSettings()
        val favoritePayload = decode<FavoritePayload>(
            preferences.getString(keyFavoritesJson, null),
        ) ?: FavoritePayload()
        val favorites = if (settings.syncEnabled) {
            favoritePayload.favorites
        } else {
            emptyList()
        }
        val lastRefreshAtMs = preferences
            .getLong(keyLastRefreshAtMs, 0L)
            .takeIf { it > 0L }
        val arrivals = decode<List<BusArrival>>(
            preferences.getString(keyArrivalsJson, null),
        )?.filter { arrival ->
            favorites.any { favorite -> favorite.id == arrival.favoriteId }
        } ?: emptyList()
        val smartSuggestion = decode<WearSmartSuggestionPayload>(
            preferences.getString(keySmartSuggestionJson, null),
        )
        val usageProfilePayload = decode<WearUsageProfilePayload>(
            preferences.getString(keyUsageProfilesJson, null),
        ) ?: WearUsageProfilePayload()

        applyState(
            context = context,
            nextState = WearHomeState(
                settings = settings,
                favorites = favorites,
                arrivals = arrivals,
                lastSyncedAtMs = listOf(
                    settings.lastUpdatedAtMs,
                    favoritePayload.lastUpdatedAtMs,
                ).filter { it > 0L }
                    .maxOrNull(),
                lastRefreshAtMs = lastRefreshAtMs,
                smartSuggestion = smartSuggestion,
                usageProfiles = usageProfilePayload.profiles,
            ),
        )

        if (settings.syncEnabled && favorites.isNotEmpty()) {
            refresh(context)
        }
    }

    fun updateSettings(
        context: Context,
        payloadJson: String,
    ) {
        ensureLoaded(context)
        val settings = decode<WearSettings>(payloadJson) ?: return
        val preferences = preferences(context)
        preferences.edit()
            .putString(keySettingsJson, payloadJson)
            .apply()

        if (!settings.syncEnabled) {
            refreshJob?.cancel()
            preferences.edit()
                .remove(keyFavoritesJson)
                .remove(keyArrivalsJson)
                .remove(keyLastRefreshAtMs)
                .apply()
            applyState(
                context = context,
                nextState = WearHomeState(
                    settings = settings,
                    lastSyncedAtMs = settings.lastUpdatedAtMs.takeIf { it > 0L }
                        ?: state.lastSyncedAtMs,
                    usageProfiles = state.usageProfiles,
                ),
            )
            return
        }

        applyState(
            context = context,
            nextState = state.copy(
                settings = settings,
                lastSyncedAtMs = settings.lastUpdatedAtMs.takeIf { it > 0L }
                    ?: state.lastSyncedAtMs,
            ),
        )
        if (state.favorites.isNotEmpty()) {
            refresh(context)
        }
    }

    fun updateFavorites(
        context: Context,
        payloadJson: String,
    ) {
        ensureLoaded(context)
        val payload = decode<FavoritePayload>(payloadJson) ?: return
        val favorites = if (state.settings.syncEnabled) {
            payload.favorites
        } else {
            emptyList()
        }

        val preferences = preferences(context)
        val editor = preferences.edit()
            .putString(keyFavoritesJson, payloadJson)
        if (favorites.isEmpty()) {
            editor.remove(keyArrivalsJson).remove(keyLastRefreshAtMs)
        }
        editor.apply()

        applyState(
            context = context,
            nextState = state.copy(
                favorites = favorites,
                arrivals = if (favorites.isEmpty()) emptyList() else state.arrivals,
                lastSyncedAtMs = payload.lastUpdatedAtMs.takeIf { it > 0L }
                    ?: state.lastSyncedAtMs,
                lastRefreshAtMs = if (favorites.isEmpty()) null else state.lastRefreshAtMs,
                lastRefreshError = null,
            ),
        )

        if (favorites.isNotEmpty()) {
            refresh(context)
        }
    }

    fun updateSmartSuggestion(context: Context, payloadJson: String) {
        ensureLoaded(context)
        val suggestion = decode<WearSmartSuggestionPayload>(payloadJson)
        val preferences = preferences(context)
        if (suggestion == null) {
            preferences.edit().remove(keySmartSuggestionJson).apply()
            applyState(context = context, nextState = state.copy(smartSuggestion = null))
            return
        }
        preferences.edit().putString(keySmartSuggestionJson, payloadJson).apply()
        applyState(
            context = context,
            nextState = state.copy(smartSuggestion = suggestion),
        )
    }

    fun updateUsageProfiles(context: Context, payloadJson: String) {
        ensureLoaded(context)
        val payload = decode<WearUsageProfilePayload>(payloadJson) ?: return
        preferences(context).edit().putString(keyUsageProfilesJson, payloadJson).apply()
        applyState(
            context = context,
            nextState = state.copy(usageProfiles = payload.profiles),
        )
        ensureLocalSmartSuggestion(context)
    }

    /**
     * When the phone has not sent a smart suggestion, derive one locally from
     * [WearHomeState.usageProfiles] so the Tile / Complication still has data.
     */
    fun ensureLocalSmartSuggestion(context: Context) {
        if (state.smartSuggestion?.source == "phone") {
            return
        }
        val provider = state.favorites.firstOrNull()?.provider
            ?: state.usageProfiles.firstOrNull()?.provider
            ?: return
        val suggestion = WearSmartRouteService.chooseSuggestion(
            profiles = state.usageProfiles,
            preferredProvider = provider,
            now = System.currentTimeMillis(),
        ) ?: return
        applyState(
            context = context,
            nextState = state.copy(smartSuggestion = suggestion),
        )
    }

    fun refresh(context: Context) {
        ensureLoaded(context)
        val favoritesSnapshot = state.favorites
        if (favoritesSnapshot.isEmpty()) {
            applyState(
                context = context,
                nextState = state.copy(
                    arrivals = emptyList(),
                    isRefreshing = false,
                    lastRefreshError = null,
                ),
            )
            return
        }

        refreshJob?.cancel()
        applyState(
            context = context,
            nextState = state.copy(
                isRefreshing = true,
                lastRefreshError = null,
            ),
        )

        refreshJob = scope.launch {
            try {
                val arrivals = BusApiService.fetchArrivals(context, favoritesSnapshot)
                val refreshedAtMs = System.currentTimeMillis()
                preferences(context).edit()
                    .putString(keyArrivalsJson, encode(arrivals))
                    .putLong(keyLastRefreshAtMs, refreshedAtMs)
                    .apply()

                applyState(
                    context = context,
                    nextState = state.copy(
                        arrivals = arrivals,
                        isRefreshing = false,
                        lastRefreshAtMs = refreshedAtMs,
                        lastRefreshError = null,
                    ),
                )
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Throwable) {
                applyState(
                    context = context,
                    nextState = state.copy(
                        isRefreshing = false,
                        lastRefreshError = error.message ?: "刷新失敗",
                    ),
                )
            }
        }
    }

    /** Suspending variant used by background workers; awaits the refresh job. */
    suspend fun refreshBlocking(context: Context) {
        refresh(context)
        refreshJob?.join()
    }

    suspend fun searchRoutes(
        context: Context,
        query: String,
    ): List<RouteSearchResult> {
        return BusApiService.searchRoutes(context, query)
    }

    suspend fun fetchRouteDetail(
        context: Context,
        routeId: String,
        provider: String,
    ): WearRouteDetail {
        return BusApiService.fetchRouteDetail(context, routeId, provider)
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(
            preferencesName,
            Context.MODE_PRIVATE,
        )

    private fun applyState(context: Context?, nextState: WearHomeState) {
        Snapshot.withMutableSnapshot {
            state = nextState
        }
        if (context != null) {
            persistTileSnapshot(context, nextState)
            notifySnapshotListeners(context)
        }
    }

    private fun persistTileSnapshot(context: Context, nextState: WearHomeState) {
        val cards = nextState.favorites.map { favorite ->
            val arrival = nextState.arrivalFor(favorite.id)
            WearArrivalCard(
                favoriteId = favorite.id,
                routeName = favorite.displayRouteName,
                stopName = favorite.displayStopName,
                etaText = arrival?.etaText ?: "--",
                etaSeconds = arrival?.arrivalEpochMs
                    ?.let { (it - System.currentTimeMillis()).coerceAtLeast(0L) / 1000L }
                    ?.toInt(),
                statusText = arrival?.statusText
                    ?: favorite.groupName.ifBlank { favorite.provider },
                routeId = favorite.realtimeRouteId.orEmpty(),
                provider = favorite.provider,
                pathId = favorite.pathId,
                stopId = favorite.stopId,
            )
        }
        val snapshot = WearTileSnapshot(
            suggestion = nextState.smartSuggestion,
            favorites = cards,
            lastUpdatedAtMs = nextState.lastRefreshAtMs
                ?: nextState.lastSyncedAtMs
                ?: System.currentTimeMillis(),
            syncEnabled = nextState.settings.syncEnabled,
        )
        preferences(context).edit()
            .putString(keyTileSnapshotJson, encode(snapshot))
            .apply()
    }

    private fun notifySnapshotListeners(context: Context) {
        val appContext = context.applicationContext
        for (listener in snapshotListeners) {
            runCatching { listener(appContext) }
        }
    }

    fun readTileSnapshot(context: Context): WearTileSnapshot {
        ensureLoaded(context)
        val raw = preferences(context).getString(keyTileSnapshotJson, null)
        return decode<WearTileSnapshot>(raw) ?: WearTileSnapshot()
    }

    private inline fun <reified T> decode(raw: String?): T? {
        if (raw.isNullOrBlank()) {
            return null
        }
        return runCatching { json.decodeFromString<T>(raw) }.getOrNull()
    }

    private inline fun <reified T> encode(value: T): String {
        return json.encodeToString(value)
    }
}
