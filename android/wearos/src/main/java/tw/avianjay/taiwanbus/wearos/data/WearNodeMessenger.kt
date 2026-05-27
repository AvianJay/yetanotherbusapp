package tw.avianjay.taiwanbus.wearos.data

import android.content.Context
import com.google.android.gms.wearable.Wearable
import java.nio.charset.StandardCharsets

object WearNodeMessenger {
    fun requestRefresh(context: Context) {
        val appContext = context.applicationContext
        Wearable.getNodeClient(appContext)
            .connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    return@addOnSuccessListener
                }

                val payload = System.currentTimeMillis()
                    .toString()
                    .toByteArray(StandardCharsets.UTF_8)
                val messageClient = Wearable.getMessageClient(appContext)
                nodes.forEach { node ->
                    messageClient.sendMessage(
                        node.id,
                        WearSyncPaths.pathRefresh,
                        payload,
                    )
                }
            }
    }
}
