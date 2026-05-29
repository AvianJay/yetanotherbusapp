package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import java.nio.charset.StandardCharsets

/**
 * Sends an `add favorite` request from the watch back to the paired phone via
 * MessageClient. The phone-side [WearableListenerService] consumes the
 * payload, decodes [WearAddFavoriteRequest] and inserts the new favorite.
 */
object WearAddFavoriteRequester {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { encodeDefaults = true }

    fun send(
        context: Context,
        routeId: String,
        routeName: String,
        provider: String,
        pathId: Int,
        pathName: String,
        stopId: Int,
        stopName: String,
    ) {
        val payload = WearAddFavoriteRequest(
            provider = provider,
            routeKey = routeId.hashCode(),
            routeId = routeId,
            routeName = routeName,
            pathId = pathId,
            pathName = pathName,
            stopId = stopId,
            stopName = stopName,
            requestedAtMs = System.currentTimeMillis(),
        )
        val bytes = json.encodeToString(payload).toByteArray(StandardCharsets.UTF_8)
        val appContext = context.applicationContext
        scope.launch {
            try {
                val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
                for (node in nodes) {
                    Wearable.getMessageClient(appContext)
                        .sendMessage(node.id, WearSyncPaths.pathAddFavorite, bytes)
                        .await()
                }
            } catch (_: Throwable) {
                // Best-effort; the phone will not insert anything if we fail.
            }
        }
    }
}
