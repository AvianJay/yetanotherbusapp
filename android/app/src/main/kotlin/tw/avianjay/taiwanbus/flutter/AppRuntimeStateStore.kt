package tw.avianjay.taiwanbus.flutter

import android.content.Context

object AppRuntimeStateStore {
    private const val PREFERENCES_NAME = "app_runtime_state"
    private const val KEY_APP_IN_FOREGROUND = "app_in_foreground"
    private const val KEY_PAUSED_PROVIDER = "trip_monitor_paused_provider"
    private const val KEY_PAUSED_ROUTE_KEY = "trip_monitor_paused_route_key"
    private const val KEY_PAUSED_PATH_ID = "trip_monitor_paused_path_id"
    private const val KEY_PAUSED_BOARDING_STOP_ID = "trip_monitor_paused_boarding_stop_id"
    private const val KEY_PAUSED_DESTINATION_STOP_ID = "trip_monitor_paused_destination_stop_id"
    private const val KEY_PAUSED_REASON = "trip_monitor_paused_reason"
    private const val KEY_PAUSED_AT_MS = "trip_monitor_paused_at_ms"

    fun setAppInForeground(context: Context, value: Boolean) {
        preferences(context).edit()
            .putBoolean(KEY_APP_IN_FOREGROUND, value)
            .apply()
    }

    fun isAppInForeground(context: Context): Boolean {
        return preferences(context).getBoolean(KEY_APP_IN_FOREGROUND, false)
    }

    fun savePausedTripMonitor(
        context: Context,
        session: TrackingSession,
        reason: String,
    ) {
        preferences(context).edit()
            .putString(KEY_PAUSED_PROVIDER, session.provider)
            .putInt(KEY_PAUSED_ROUTE_KEY, session.routeKey)
            .putInt(KEY_PAUSED_PATH_ID, session.pathId)
            .putInt(KEY_PAUSED_BOARDING_STOP_ID, session.boardingStopId ?: -1)
            .putInt(KEY_PAUSED_DESTINATION_STOP_ID, session.destinationStopId ?: -1)
            .putString(KEY_PAUSED_REASON, reason)
            .putLong(KEY_PAUSED_AT_MS, System.currentTimeMillis())
            .apply()
    }

    fun clearPausedTripMonitor(context: Context) {
        preferences(context).edit()
            .remove(KEY_PAUSED_PROVIDER)
            .remove(KEY_PAUSED_ROUTE_KEY)
            .remove(KEY_PAUSED_PATH_ID)
            .remove(KEY_PAUSED_BOARDING_STOP_ID)
            .remove(KEY_PAUSED_DESTINATION_STOP_ID)
            .remove(KEY_PAUSED_REASON)
            .remove(KEY_PAUSED_AT_MS)
            .apply()
    }

    fun loadPausedTripMonitor(context: Context): TripMonitorPauseState? {
        val preferences = preferences(context)
        val provider = preferences.getString(KEY_PAUSED_PROVIDER, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        val routeKey = preferences.getInt(KEY_PAUSED_ROUTE_KEY, 0)
        val pathId = preferences.getInt(KEY_PAUSED_PATH_ID, Int.MIN_VALUE)
        if (routeKey <= 0 || pathId == Int.MIN_VALUE) {
            return null
        }
        return TripMonitorPauseState(
            provider = provider,
            routeKey = routeKey,
            pathId = pathId,
            boardingStopId = preferences.getInt(KEY_PAUSED_BOARDING_STOP_ID, -1)
                .takeIf { it > 0 },
            destinationStopId = preferences.getInt(KEY_PAUSED_DESTINATION_STOP_ID, -1)
                .takeIf { it > 0 },
            reason = preferences.getString(KEY_PAUSED_REASON, null)
                ?.trim()
                ?.takeIf { it.isNotEmpty() },
            pausedAtMs = preferences.getLong(KEY_PAUSED_AT_MS, 0L),
        )
    }

    fun isTripMonitorPausedFor(
        context: Context,
        session: TrackingSession,
    ): Boolean {
        return loadPausedTripMonitor(context)?.matches(session) == true
    }

    private fun preferences(context: Context) = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )
}

data class TripMonitorPauseState(
    val provider: String,
    val routeKey: Int,
    val pathId: Int,
    val boardingStopId: Int?,
    val destinationStopId: Int?,
    val reason: String?,
    val pausedAtMs: Long,
) {
    fun matches(session: TrackingSession): Boolean {
        return provider == session.provider &&
            routeKey == session.routeKey &&
            pathId == session.pathId &&
            boardingStopId == session.boardingStopId &&
            destinationStopId == session.destinationStopId
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "provider" to provider,
            "routeKey" to routeKey,
            "pathId" to pathId,
            "boardingStopId" to boardingStopId,
            "destinationStopId" to destinationStopId,
            "reason" to reason,
            "pausedAtMs" to pausedAtMs,
        )
    }
}
