package tw.avianjay.taiwanbus.wearos.data

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class WearSyncListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) {
                continue
            }

            val path = event.dataItem.uri.path ?: continue
            val payloadJson = DataMapItem.fromDataItem(event.dataItem)
                .dataMap
                .getString(WearSyncPaths.keyPayloadJson)
                ?: continue

            when (path) {
                WearSyncPaths.pathSettings ->
                    WearDataRepository.updateSettings(this, payloadJson)

                WearSyncPaths.pathFavorites ->
                    WearDataRepository.updateFavorites(this, payloadJson)

                WearSyncPaths.pathSmartSuggestion ->
                    WearDataRepository.updateSmartSuggestion(this, payloadJson)

                WearSyncPaths.pathUsageProfiles ->
                    WearDataRepository.updateUsageProfiles(this, payloadJson)
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            WearSyncPaths.pathRefresh -> {
                WearDataRepository.refresh(this)
                return
            }

            WearSyncPaths.pathCancelRefresh -> {
                WearRefreshScheduler.cancel(this)
                return
            }
        }
        super.onMessageReceived(messageEvent)
    }
}
