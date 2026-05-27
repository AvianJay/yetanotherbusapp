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

    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var refreshJob: Job? = null
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
        } ?: emptyList()

        applyState(
            WearHomeState(
                settings = settings,
                favorites = favorites,
                arrivals = arrivals,
                lastSyncedAtMs = listOf(
                    settings.lastUpdatedAtMs,
                    favoritePayload.lastUpdatedAtMs,
                ).filter { it > 0L }
                    .maxOrNull(),
                lastRefreshAtMs = lastRefreshAtMs,
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
                WearHomeState(
                    settings = settings,
                    lastSyncedAtMs = settings.lastUpdatedAtMs.takeIf { it > 0L }
                        ?: state.lastSyncedAtMs,
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
            state.copy(
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

    fun refresh(context: Context) {
        ensureLoaded(context)
        val favoritesSnapshot = state.favorites
        if (favoritesSnapshot.isEmpty()) {
            applyState(
                state.copy(
                    arrivals = emptyList(),
                    isRefreshing = false,
                    lastRefreshError = null,
                ),
            )
            return
        }

        refreshJob?.cancel()
        applyState(
            state.copy(
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
                    state.copy(
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
                    state.copy(
                        isRefreshing = false,
                        lastRefreshError = error.message ?: "Realtime refresh failed.",
                    ),
                )
            }
        }
    }

    suspend fun searchRoutes(
        context: Context,
        query: String,
    ): List<RouteSearchResult> {
        return BusApiService.searchRoutes(context, query)
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
