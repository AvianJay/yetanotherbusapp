package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules the periodic [WearRefreshWorker]. The 15-minute floor is imposed
 * by Android's PeriodicWorkRequest minimum interval.
 */
object WearRefreshScheduler {
    private const val WORK_NAME = "yabus_wear_refresh"
    private const val INTERVAL_MINUTES = 15L
    private const val FLEX_MINUTES = 5L

    fun schedulePeriodic(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = PeriodicWorkRequestBuilder<WearRefreshWorker>(
            INTERVAL_MINUTES,
            TimeUnit.MINUTES,
            FLEX_MINUTES,
            TimeUnit.MINUTES,
        )
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context.applicationContext)
            .cancelUniqueWork(WORK_NAME)
    }
}
