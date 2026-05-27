package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import kotlinx.serialization.json.Json

object WearDataRepository {
    private const val preferencesName = "wear_sync_state"
    private const val keySettingsJson = "settings_json"
    private const val keyFavoritesJson = "favorites_json"
    private const val keyArrivalsJson = "arrivals_json"
    private const val keyLastRefreshAtMs = "last_refresh_at_ms"

    private val json = Json { ignoreUnknownKeys = true }
    private val dataSource: BusDataSource = MockBusDataSource
    private var loaded = false

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
        } ?: buildArrivals(
            favorites = favorites,
            updatedAtMs = lastRefreshAtMs ?: System.currentTimeMillis(),
        )

        applyState(
            WearHomeState(
                settings = settings,
                favorites = favorites,
                arrivals = if (favorites.isEmpty()) emptyList() else arrivals,
                lastSyncedAtMs = listOf(
                    settings.lastUpdatedAtMs,
                    favoritePayload.lastUpdatedAtMs,
                ).filter { it > 0L }
                    .maxOrNull(),
                lastRefreshAtMs = lastRefreshAtMs,
            ),
        )
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
            preferences.edit()
                .remove(keyFavoritesJson)
                .remove(keyArrivalsJson)
                .apply()
            applyState(
                WearHomeState(
                    settings = settings,
                    lastSyncedAtMs = settings.lastUpdatedAtMs.takeIf { it > 0L }
                        ?: state.lastSyncedAtMs,
                    lastRefreshAtMs = state.lastRefreshAtMs,
                ),
            )
            return
        }

        applyState(
            state.copy(
                settings = settings,
                lastSyncedAtMs = settings.lastUpdatedAtMs.takeIf { it > 0L }
                    ?: state.lastSyncedAtMs,
            ),
        )
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
        val refreshedAtMs = System.currentTimeMillis()
        val arrivals = buildArrivals(
            favorites = favorites,
            updatedAtMs = refreshedAtMs,
        )

        val preferences = preferences(context)
        preferences.edit()
            .putString(keyFavoritesJson, payloadJson)
            .putString(keyArrivalsJson, encode(arrivals))
            .putLong(keyLastRefreshAtMs, refreshedAtMs)
            .apply()

        applyState(
            state.copy(
                favorites = favorites,
                arrivals = arrivals,
                lastSyncedAtMs = payload.lastUpdatedAtMs.takeIf { it > 0L }
                    ?: state.lastSyncedAtMs,
                lastRefreshAtMs = refreshedAtMs.takeIf { favorites.isNotEmpty() },
            ),
        )
    }

    fun refresh(context: Context) {
        ensureLoaded(context)
        val refreshedAtMs = System.currentTimeMillis()
        val arrivals = buildArrivals(
            favorites = state.favorites,
            updatedAtMs = refreshedAtMs,
        )
        preferences(context).edit()
            .putString(keyArrivalsJson, encode(arrivals))
            .putLong(keyLastRefreshAtMs, refreshedAtMs)
            .apply()

        applyState(
            state.copy(
                arrivals = arrivals,
                lastRefreshAtMs = refreshedAtMs.takeIf { state.favorites.isNotEmpty() },
            ),
        )
    }

    fun searchRoutes(query: String): List<RouteSearchResult> {
        return dataSource.searchRoutes(query)
    }

    private fun buildArrivals(
        favorites: List<FavoriteStop>,
        updatedAtMs: Long,
    ): List<BusArrival> {
        if (favorites.isEmpty()) {
            return emptyList()
        }
        return dataSource.buildArrivals(favorites, updatedAtMs)
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(
            preferencesName,
            Context.MODE_PRIVATE,
        )

    private fun applyState(nextState: WearHomeState) {
        Snapshot.withMutableSnapshot {
            state = nextState
        }
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
