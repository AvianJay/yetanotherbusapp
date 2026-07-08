package tw.avianjay.taiwanbus.flutter

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import org.json.JSONObject

object FavoriteWidgetRefreshScheduler {
    private const val WORK_NAME = "favorite_widget_refresh"
    private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val SETTINGS_KEY = "flutter.app_settings"
    private const val SETTINGS_FALLBACK_KEY = "app_settings"
    private const val SETTINGS_REFRESH_MINUTES_KEY = "favoriteWidgetAutoRefreshMinutes"

    fun sync(context: Context, minutes: Int) {
        // WorkManager may be unavailable in stripped-down widget-host starts;
        // scheduling is best-effort and must never crash the caller.
        runCatching {
            val workManager = WorkManager.getInstance(context)
            if (minutes < 15 || !hasAnyFavoriteWidgets(context)) {
                workManager.cancelUniqueWork(WORK_NAME)
                return
            }

            val request = PeriodicWorkRequestBuilder<FavoriteWidgetRefreshWorker>(
                minutes.toLong(),
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
    }

    fun syncFromPreferences(context: Context) {
        sync(context, loadRefreshMinutesFromPreferences(context))
    }

    private fun hasAnyFavoriteWidgets(context: Context): Boolean {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, FavoriteGroupWidgetProvider::class.java),
        )
        return widgetIds.isNotEmpty()
    }

    private fun loadRefreshMinutesFromPreferences(context: Context): Int {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(SETTINGS_KEY, null)
            ?: preferences.getString(SETTINGS_FALLBACK_KEY, null)
            ?: return 0
        return try {
            JSONObject(raw).optInt(SETTINGS_REFRESH_MINUTES_KEY, 0)
        } catch (_: Exception) {
            0
        }
    }
}
