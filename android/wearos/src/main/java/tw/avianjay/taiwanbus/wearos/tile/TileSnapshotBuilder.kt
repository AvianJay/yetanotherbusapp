package tw.avianjay.taiwanbus.wearos.tile

import android.content.Context
import tw.avianjay.taiwanbus.wearos.data.WearDataRepository
import tw.avianjay.taiwanbus.wearos.data.WearTileSnapshot

/**
 * Thin wrapper that loads the latest [WearTileSnapshot] for both
 * [YaBusTileService] and [tw.avianjay.taiwanbus.wearos.complication.NextBusComplicationService].
 *
 * The actual snapshot persistence lives inside [WearDataRepository]; this
 * builder just guarantees that a value is available even on a cold start.
 */
object TileSnapshotBuilder {
    fun read(context: Context): WearTileSnapshot {
        WearDataRepository.ensureLoaded(context)
        return WearDataRepository.readTileSnapshot(context)
    }
}
