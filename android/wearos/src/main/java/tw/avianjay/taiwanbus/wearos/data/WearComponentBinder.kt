package tw.avianjay.taiwanbus.wearos.data

import android.content.ComponentName
import android.content.Context
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import tw.avianjay.taiwanbus.wearos.complication.NextBusComplicationService
import tw.avianjay.taiwanbus.wearos.tile.YaBusTileService

/**
 * Wires [WearDataRepository] changes to the system's Tile and Complication
 * update channels. Called once from [tw.avianjay.taiwanbus.wearos.presentation.MainActivity]
 * (process start) and from [WearSyncListenerService] (when Wearable APIs
 * spin the service up without launching the activity).
 */
object WearComponentBinder {
    @Volatile
    private var attached = false

    fun attach(context: Context) {
        if (attached) return
        synchronized(this) {
            if (attached) return
            attached = true
            val appContext = context.applicationContext
            WearDataRepository.registerSnapshotListener { ctx ->
                YaBusTileService.requestUpdate(ctx)
                requestComplicationUpdate(ctx)
            }
            // Trigger an initial Tile/Complication refresh so cold launches
            // re-render with the latest cached snapshot.
            YaBusTileService.requestUpdate(appContext)
            requestComplicationUpdate(appContext)
        }
    }

    private fun requestComplicationUpdate(context: Context) {
        try {
            val component = ComponentName(context, NextBusComplicationService::class.java)
            ComplicationDataSourceUpdateRequester
                .create(context.applicationContext, component)
                .requestUpdateAll()
        } catch (_: Throwable) {
            // Complication may not be added by user yet; ignore.
        }
    }
}
