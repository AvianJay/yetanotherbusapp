package tw.avianjay.taiwanbus.flutter

import android.content.Context
import android.content.Intent

object AppLaunchConstants {
    const val TARGET_ROUTE_DETAIL = "route_detail"
    const val TARGET_FAVORITES_GROUP = "favorites_group"

    private const val EXTRA_TARGET = "launch_target"
    private const val EXTRA_PROVIDER = "provider"
    private const val EXTRA_ROUTE_KEY = "route_key"
    private const val EXTRA_PATH_ID = "path_id"
    private const val EXTRA_STOP_ID = "stop_id"
    private const val EXTRA_DESTINATION_PATH_ID = "destination_path_id"
    private const val EXTRA_DESTINATION_STOP_ID = "destination_stop_id"
    private const val EXTRA_GROUP_NAME = "group_name"

    fun createRouteDetailIntent(
        context: Context,
        provider: String,
        routeKey: Int,
        pathId: Int,
        stopId: Int,
        destinationPathId: Int? = null,
        destinationStopId: Int? = null,
    ): Intent {
        return Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_TARGET, TARGET_ROUTE_DETAIL)
            putExtra(EXTRA_PROVIDER, provider)
            putExtra(EXTRA_ROUTE_KEY, routeKey)
            putExtra(EXTRA_PATH_ID, pathId)
            putExtra(EXTRA_STOP_ID, stopId)
            if (destinationPathId != null) {
                putExtra(EXTRA_DESTINATION_PATH_ID, destinationPathId)
            }
            if (destinationStopId != null) {
                putExtra(EXTRA_DESTINATION_STOP_ID, destinationStopId)
            }
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    fun createFavoritesGroupIntent(
        context: Context,
        groupName: String,
    ): Intent {
        return Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_TARGET, TARGET_FAVORITES_GROUP)
            putExtra(EXTRA_GROUP_NAME, groupName)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    fun extractLaunchPayload(intent: Intent?): Map<String, Any?>? {
        intent ?: return null
        val target = intent.getStringExtra(EXTRA_TARGET)?.trim().orEmpty()
        if (target.isEmpty()) {
            return null
        }

        return when (target) {
            TARGET_ROUTE_DETAIL -> {
                val provider = intent.getStringExtra(EXTRA_PROVIDER) ?: return null
                val routeKey = intent.getIntExtra(EXTRA_ROUTE_KEY, Int.MIN_VALUE)
                if (routeKey == Int.MIN_VALUE) {
                    return null
                }
                val payload = mutableMapOf<String, Any?>(
                    "target" to TARGET_ROUTE_DETAIL,
                    "provider" to provider,
                    "routeKey" to routeKey,
                    "pathId" to intent.getIntExtra(EXTRA_PATH_ID, 0),
                    "stopId" to intent.getIntExtra(EXTRA_STOP_ID, 0),
                )
                val destinationPathId = intent.getIntExtra(
                    EXTRA_DESTINATION_PATH_ID,
                    Int.MIN_VALUE,
                )
                if (destinationPathId != Int.MIN_VALUE) {
                    payload["destinationPathId"] = destinationPathId
                }
                val destinationStopId = intent.getIntExtra(
                    EXTRA_DESTINATION_STOP_ID,
                    Int.MIN_VALUE,
                )
                if (destinationStopId != Int.MIN_VALUE) {
                    payload["destinationStopId"] = destinationStopId
                }
                payload
            }

            TARGET_FAVORITES_GROUP -> {
                val groupName = intent.getStringExtra(EXTRA_GROUP_NAME) ?: return null
                mapOf(
                    "target" to TARGET_FAVORITES_GROUP,
                    "groupName" to groupName,
                )
            }

            else -> null
        }
    }
}
