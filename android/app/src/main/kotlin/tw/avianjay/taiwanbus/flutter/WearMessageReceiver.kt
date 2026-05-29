package tw.avianjay.taiwanbus.flutter

import android.os.Handler
import android.os.Looper
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import io.flutter.plugin.common.EventChannel
import java.nio.charset.StandardCharsets

/**
 * Receives messages from the paired Wear OS app. Currently handles the
 * `add favorite` request, forwarding the JSON payload to Flutter via the
 * shared event channel registered in [MainActivity].
 */
class WearMessageReceiver : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            PATH_ADD_FAVORITE -> dispatch(messageEvent, kind = "add_favorite")
            PATH_OPEN_ROUTE -> dispatch(messageEvent, kind = "open_route")
            else -> super.onMessageReceived(messageEvent)
        }
    }

    private fun dispatch(event: MessageEvent, kind: String) {
        val payload = String(event.data, StandardCharsets.UTF_8)
        WearEventBridge.dispatch(
            mapOf(
                "kind" to kind,
                "payloadJson" to payload,
                "receivedAtMs" to System.currentTimeMillis(),
            ),
        )
    }

    companion object {
        const val PATH_ADD_FAVORITE = "/wear/add_favorite"
        const val PATH_OPEN_ROUTE = "/wear/open_route"
    }
}

/**
 * Tiny in-memory bridge so [WearMessageReceiver] (background service) and the
 * [io.flutter.embedding.engine.FlutterEngine]-owned event channel can talk
 * even if a message arrives before Flutter is fully bound.
 */
object WearEventBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<Map<String, Any?>>()

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(sink: EventChannel.EventSink?) {
        this.sink = sink
        if (sink != null) {
            while (pending.isNotEmpty()) {
                val message = pending.removeFirst()
                mainHandler.post { sink.success(message) }
            }
        }
    }

    fun detach() {
        this.sink = null
    }

    fun dispatch(message: Map<String, Any?>) {
        val current = sink
        if (current != null) {
            mainHandler.post { current.success(message) }
        } else {
            // Cap the queue so a long-detached engine doesn't grow unbounded.
            if (pending.size >= 16) pending.removeFirst()
            pending.addLast(message)
        }
    }
}
