package tw.avianjay.taiwanbus.wearos.complication

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import tw.avianjay.taiwanbus.wearos.R
import tw.avianjay.taiwanbus.wearos.data.WearArrivalCard
import tw.avianjay.taiwanbus.wearos.data.WearSmartSuggestionPayload
import tw.avianjay.taiwanbus.wearos.data.WearTileSnapshot
import tw.avianjay.taiwanbus.wearos.presentation.MainActivity
import tw.avianjay.taiwanbus.wearos.tile.TileSnapshotBuilder

/**
 * Surfaces the next-bus arrival on watch face complications. The snapshot is
 * shared with [tw.avianjay.taiwanbus.wearos.tile.YaBusTileService] so the
 * complication and tile stay in lockstep without extra network calls.
 */
class NextBusComplicationService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return buildData(
            type = type,
            primaryText = "5 分",
            secondaryText = getString(R.string.complication_label),
            longText = "5 分 · 信義國中",
            rangedValueMinutes = 5f,
            tapIntent = null,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val snapshot = TileSnapshotBuilder.read(this)
        val (primary, secondary, longText, minutes, routeId, provider) = pickFromSnapshot(snapshot)
            ?: return getPreviewData(request.complicationType)
                ?.let { fallback ->
                    when (fallback) {
                        is ShortTextComplicationData -> ShortTextComplicationData.Builder(
                            text = PlainComplicationText.Builder("--").build(),
                            contentDescription = PlainComplicationText.Builder(
                                getString(R.string.complication_description),
                            ).build(),
                        ).build()

                        else -> fallback
                    }
                }

        val tapIntent = buildTapPendingIntent(routeId, provider)
        return buildData(
            type = request.complicationType,
            primaryText = primary,
            secondaryText = secondary,
            longText = longText,
            rangedValueMinutes = minutes,
            tapIntent = tapIntent,
        )
    }

    private data class ComplicationSlots(
        val primary: String,
        val secondary: String,
        val longText: String,
        val minutes: Float,
        val routeId: String?,
        val provider: String?,
    )

    private fun pickFromSnapshot(snapshot: WearTileSnapshot): ComplicationSlots? {
        snapshot.suggestion?.let { suggestion ->
            return suggestion.toSlots()
        }
        val favorite = snapshot.favorites.firstOrNull() ?: return null
        return favorite.toSlots()
    }

    private fun WearSmartSuggestionPayload.toSlots(): ComplicationSlots {
        val minutes = etaSeconds?.let { (it / 60f).coerceAtLeast(0f).coerceAtMost(MAX_MINUTES) }
            ?: 0f
        val primary = etaText?.takeIf { it.isNotBlank() } ?: routeName.ifBlank { routeId }
        val stop = stopName.ifBlank { reason.ifBlank { getString(R.string.complication_description) } }
        return ComplicationSlots(
            primary = primary,
            secondary = routeName.ifBlank { routeId },
            longText = "${routeName.ifBlank { routeId }} · $stop",
            minutes = minutes,
            routeId = routeId.takeIf { it.isNotBlank() },
            provider = provider.takeIf { it.isNotBlank() },
        )
    }

    private fun WearArrivalCard.toSlots(): ComplicationSlots {
        val minutes = etaSeconds?.let { (it / 60f).coerceAtLeast(0f).coerceAtMost(MAX_MINUTES) }
            ?: 0f
        return ComplicationSlots(
            primary = etaText.ifBlank { "--" },
            secondary = routeName,
            longText = "$routeName · $stopName",
            minutes = minutes,
            routeId = routeId.takeIf { it.isNotBlank() },
            provider = provider.takeIf { it.isNotBlank() },
        )
    }

    private fun buildData(
        type: ComplicationType,
        primaryText: String,
        secondaryText: String,
        longText: String,
        rangedValueMinutes: Float,
        tapIntent: PendingIntent?,
    ): ComplicationData? {
        val contentDescription = PlainComplicationText.Builder(
            getString(R.string.complication_description),
        ).build()
        val icon = MonochromaticImage.Builder(
            Icon.createWithResource(this, R.drawable.ic_complication_bus),
        ).build()

        return when (type) {
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder(primaryText).build(),
                contentDescription = contentDescription,
            )
                .setTitle(PlainComplicationText.Builder(secondaryText).build())
                .setMonochromaticImage(icon)
                .apply { tapIntent?.let { setTapAction(it) } }
                .build()

            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(
                text = PlainComplicationText.Builder(longText).build(),
                contentDescription = contentDescription,
            )
                .setTitle(PlainComplicationText.Builder(secondaryText).build())
                .setMonochromaticImage(icon)
                .apply { tapIntent?.let { setTapAction(it) } }
                .build()

            ComplicationType.RANGED_VALUE -> RangedValueComplicationData.Builder(
                value = rangedValueMinutes,
                min = 0f,
                max = MAX_MINUTES,
                contentDescription = contentDescription,
            )
                .setText(PlainComplicationText.Builder(primaryText).build())
                .setTitle(PlainComplicationText.Builder(secondaryText).build())
                .setMonochromaticImage(icon)
                .apply { tapIntent?.let { setTapAction(it) } }
                .build()

            else -> null
        }
    }

    private fun buildTapPendingIntent(
        routeId: String?,
        provider: String?,
    ): PendingIntent {
        val uri = if (routeId.isNullOrBlank()) {
            Uri.parse("yabus-wear://search")
        } else {
            Uri.parse("yabus-wear://route/$routeId?provider=${provider.orEmpty()}")
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            setClass(this@NextBusComplicationService, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            this,
            uri.toString().hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        private const val MAX_MINUTES = 30f
    }
}
