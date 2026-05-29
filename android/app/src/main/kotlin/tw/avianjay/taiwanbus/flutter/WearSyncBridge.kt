package tw.avianjay.taiwanbus.flutter

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets

class WearSyncBridge(
    context: Context,
) {
    private val appContext = context.applicationContext

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "syncWearSettings" -> {
                syncPayload(
                    path = PATH_SETTINGS,
                    payloadJson = call.argument<String>("payloadJson"),
                    errorCode = "wear_settings_sync_failed",
                    result = result,
                )
                true
            }

            "syncWearFavorites" -> {
                syncPayload(
                    path = PATH_FAVORITES,
                    payloadJson = call.argument<String>("payloadJson"),
                    errorCode = "wear_favorites_sync_failed",
                    result = result,
                )
                true
            }

            "syncWearSmartSuggestion" -> {
                syncPayload(
                    path = PATH_SMART_SUGGESTION,
                    payloadJson = call.argument<String>("payloadJson"),
                    errorCode = "wear_smart_suggestion_sync_failed",
                    result = result,
                )
                true
            }

            "clearWearSmartSuggestion" -> {
                clearDataItem(
                    path = PATH_SMART_SUGGESTION,
                    errorCode = "wear_smart_suggestion_clear_failed",
                    result = result,
                )
                true
            }

            "syncWearUsageProfiles" -> {
                syncPayload(
                    path = PATH_USAGE_PROFILES,
                    payloadJson = call.argument<String>("payloadJson"),
                    errorCode = "wear_usage_profiles_sync_failed",
                    result = result,
                )
                true
            }

            "cancelWearRefresh" -> {
                sendBroadcastMessage(
                    path = PATH_CANCEL_REFRESH,
                    errorCode = "wear_cancel_refresh_failed",
                    result = result,
                )
                true
            }

            "requestWearRefresh" -> {
                requestRefresh(result)
                true
            }

            "getWearSyncStatus" -> {
                loadStatus(result)
                true
            }

            else -> false
        }
    }

    private fun syncPayload(
        path: String,
        payloadJson: String?,
        errorCode: String,
        result: MethodChannel.Result,
    ) {
        if (payloadJson.isNullOrBlank()) {
            result.error("missing_payload", "payloadJson is required.", null)
            return
        }

        val request = PutDataMapRequest.create(path).apply {
            dataMap.putString(KEY_PAYLOAD_JSON, payloadJson)
            dataMap.putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(appContext)
            .putDataItem(request)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error(errorCode, error.message, null)
            }
    }

    private fun requestRefresh(result: MethodChannel.Result) {
        Wearable.getNodeClient(appContext)
            .connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    result.success(null)
                    return@addOnSuccessListener
                }

                val payload = System.currentTimeMillis()
                    .toString()
                    .toByteArray(StandardCharsets.UTF_8)
                val tasks = nodes.map { node ->
                    Wearable.getMessageClient(appContext)
                        .sendMessage(node.id, PATH_REFRESH, payload)
                }
                completeAll(
                    tasks = tasks,
                    errorCode = "wear_refresh_failed",
                    errorMessage = "Failed to notify Wear OS nodes to refresh.",
                    result = result,
                )
            }
            .addOnFailureListener { error ->
                result.error("wear_status_failed", error.message, null)
            }
    }

    private fun loadStatus(result: MethodChannel.Result) {
        Wearable.getNodeClient(appContext)
            .connectedNodes
            .addOnSuccessListener { nodes ->
                result.success(
                    mapOf(
                        "connectedNodeCount" to nodes.size,
                        "connectedNodeNames" to nodes.map { it.displayName },
                    ),
                )
            }
            .addOnFailureListener { error ->
                result.error("wear_status_failed", error.message, null)
            }
    }

    private fun completeAll(
        tasks: List<Task<Int>>,
        errorCode: String,
        errorMessage: String,
        result: MethodChannel.Result,
    ) {
        Tasks.whenAllComplete(tasks)
            .addOnCompleteListener {
                val failed = tasks.firstOrNull { !it.isSuccessful }
                if (failed != null) {
                    result.error(
                        errorCode,
                        failed.exception?.message ?: errorMessage,
                        null,
                    )
                    return@addOnCompleteListener
                }
                result.success(null)
            }
            .addOnFailureListener { error ->
                result.error(errorCode, error.message ?: errorMessage, null)
            }
    }

    private fun clearDataItem(
        path: String,
        errorCode: String,
        result: MethodChannel.Result,
    ) {
        Wearable.getDataClient(appContext)
            .deleteDataItems(android.net.Uri.parse("wear:$path"))
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error(errorCode, error.message, null)
            }
    }

    private fun sendBroadcastMessage(
        path: String,
        errorCode: String,
        result: MethodChannel.Result,
    ) {
        Wearable.getNodeClient(appContext)
            .connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    result.success(null)
                    return@addOnSuccessListener
                }
                val payload = System.currentTimeMillis()
                    .toString()
                    .toByteArray(StandardCharsets.UTF_8)
                val tasks = nodes.map { node ->
                    Wearable.getMessageClient(appContext)
                        .sendMessage(node.id, path, payload)
                }
                completeAll(
                    tasks = tasks,
                    errorCode = errorCode,
                    errorMessage = "Failed to broadcast message to Wear OS nodes.",
                    result = result,
                )
            }
            .addOnFailureListener { error ->
                result.error(errorCode, error.message, null)
            }
    }

    companion object {
        private const val KEY_PAYLOAD_JSON = "payload_json"
        private const val KEY_UPDATED_AT_MS = "updated_at_ms"
        private const val PATH_SETTINGS = "/wear/settings"
        private const val PATH_FAVORITES = "/wear/favorites"
        private const val PATH_SMART_SUGGESTION = "/wear/smart_suggestion"
        private const val PATH_USAGE_PROFILES = "/wear/usage_profiles"
        private const val PATH_REFRESH = "/wear/refresh"
        private const val PATH_CANCEL_REFRESH = "/wear/cancel_refresh"
    }
}
