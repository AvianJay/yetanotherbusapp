package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Periodic worker that refreshes favorite ETAs in the background. The refresh
 * goes through [WearDataRepository] which in turn re-renders the Tile and
 * Complication via [WearComponentBinder] snapshot listeners.
 */
class WearRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        return try {
            WearDataRepository.ensureLoaded(applicationContext)
            WearComponentBinder.attach(applicationContext)
            if (WearDataRepository.state.settings.syncEnabled &&
                WearDataRepository.state.favorites.isNotEmpty()
            ) {
                WearDataRepository.refreshBlocking(applicationContext)
            } else {
                // Even without favorites, push fresh Tile/Complication content
                // (smart suggestion may have updated).
                WearDataRepository.ensureLocalSmartSuggestion(applicationContext)
            }
            Result.success()
        } catch (error: Throwable) {
            // Retry up to the WorkManager default policy.
            if (runAttemptCount < 3) Result.retry() else Result.success()
        }
    }
}
