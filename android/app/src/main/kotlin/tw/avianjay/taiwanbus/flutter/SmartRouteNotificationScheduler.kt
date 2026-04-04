package tw.avianjay.taiwanbus.flutter

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

object SmartRouteNotificationScheduler {
    private const val WORK_NAME = "smart_route_notification_refresh"
    private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val SETTINGS_KEY = "flutter.app_settings"
    private const val SETTINGS_FALLBACK_KEY = "app_settings"
    private const val ROUTE_USAGE_KEY = "flutter.route_usage_profiles"
    private const val ROUTE_USAGE_FALLBACK_KEY = "route_usage_profiles"
    private const val SETTINGS_NOTIFICATIONS_ENABLED_KEY = "enableSmartRouteNotifications"

    fun sync(context: Context, enabled: Boolean) {
        val workManager = WorkManager.getInstance(context)
        if (!enabled || !hasLearnedRoutes(context)) {
            workManager.cancelUniqueWork(WORK_NAME)
            return
        }

        val request = PeriodicWorkRequestBuilder<SmartRouteNotificationWorker>(
            15,
            TimeUnit.MINUTES,
        ).setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build(),
        ).build()

        workManager.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun syncFromPreferences(context: Context) {
        sync(context, loadEnabledFromPreferences(context))
    }

    private fun loadEnabledFromPreferences(context: Context): Boolean {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(SETTINGS_KEY, null)
            ?: preferences.getString(SETTINGS_FALLBACK_KEY, null)
            ?: return false
        return try {
            JSONObject(raw).optBoolean(SETTINGS_NOTIFICATIONS_ENABLED_KEY, false)
        } catch (_: Exception) {
            false
        }
    }

    private fun hasLearnedRoutes(context: Context): Boolean {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(ROUTE_USAGE_KEY, null)
            ?: preferences.getString(ROUTE_USAGE_FALLBACK_KEY, null)
            ?: return false
        return try {
            JSONArray(raw).length() > 0
        } catch (_: Exception) {
            false
        }
    }
}
