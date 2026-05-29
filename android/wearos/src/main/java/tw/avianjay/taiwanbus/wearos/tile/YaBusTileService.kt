package tw.avianjay.taiwanbus.wearos.tile

import android.content.Context
import android.net.Uri
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.DimensionBuilders.wrap
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.FONT_WEIGHT_BOLD
import androidx.wear.protolayout.LayoutElementBuilders.FONT_WEIGHT_MEDIUM
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_START
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.Futures
import tw.avianjay.taiwanbus.wearos.R
import tw.avianjay.taiwanbus.wearos.data.WearArrivalCard
import tw.avianjay.taiwanbus.wearos.data.WearDataRepository
import tw.avianjay.taiwanbus.wearos.data.WearSmartSuggestionPayload
import tw.avianjay.taiwanbus.wearos.data.WearTileSnapshot
import tw.avianjay.taiwanbus.wearos.presentation.MainActivity

/**
 * Tile entry point. The layout shows (in order):
 *  1. A smart-recommendation header card when a suggestion is present.
 *  2. Up to three compact favorite arrival rows.
 *  3. A bottom "search" pill that opens the watch app.
 *
 * The snapshot is read from [WearDataRepository]; tile updates are triggered
 * by [tw.avianjay.taiwanbus.wearos.data.WearSyncListenerService] and the
 * periodic [tw.avianjay.taiwanbus.wearos.data.WearRefreshWorker].
 */
class YaBusTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        val snapshot = TileSnapshotBuilder.read(this)
        val protoParams = getProtoDeviceParams(requestParams.deviceParameters)
        val layout = buildLayout(this, snapshot, protoParams)
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(FRESHNESS_INTERVAL_MS)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(
                        TimelineBuilders.TimelineEntry.Builder()
                            .setLayout(
                                LayoutElementBuilders.Layout.Builder()
                                    .setRoot(layout)
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .addIdToImageMapping(
                IMAGE_BUS,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(R.drawable.ic_complication_bus)
                            .build(),
                    )
                    .build(),
            )
            .build()
        return Futures.immediateFuture(resources)
    }

    private fun buildLayout(
        context: Context,
        snapshot: WearTileSnapshot,
        deviceParams: androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters,
    ): LayoutElementBuilders.LayoutElement {
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)

        val suggestion = snapshot.suggestion
        if (suggestion != null) {
            column.addContent(suggestionCard(context, suggestion))
            column.addContent(spacer(6))
        }

        val favorites = snapshot.favorites.take(MAX_FAVORITES)
        if (favorites.isEmpty() && suggestion == null) {
            column.addContent(emptyState(context, snapshot))
        } else {
            favorites.forEach { favorite ->
                column.addContent(favoriteRow(context, favorite))
                column.addContent(spacer(4))
            }
        }

        return PrimaryLayout.Builder(deviceParams)
            .setContent(column.build())
            .setPrimaryChipContent(footerButton(context))
            .build()
    }

    private fun getProtoDeviceParams(
        tilesParams: androidx.wear.tiles.DeviceParametersBuilders.DeviceParameters?,
    ): androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters {
        val builder = androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters.Builder()
        if (tilesParams != null) {
            builder.setScreenShape(tilesParams.screenShape)
                .setScreenWidthDp(tilesParams.screenWidthDp)
                .setScreenHeightDp(tilesParams.screenHeightDp)
                .setScreenDensity(tilesParams.screenDensity)
        } else {
            builder.setScreenShape(androidx.wear.protolayout.DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
                .setScreenWidthDp(192)
                .setScreenHeightDp(192)
                .setScreenDensity(1.0f)
        }
        return builder.build()
    }

    private fun suggestionCard(
        context: Context,
        suggestion: WearSmartSuggestionPayload,
    ): LayoutElementBuilders.LayoutElement {
        val titleText = suggestion.routeName.ifBlank { suggestion.routeId }
        val subtitleParts = buildList {
            suggestion.etaText?.takeIf { it.isNotBlank() }?.let { add(it) }
            suggestion.stopName.takeIf { it.isNotBlank() }?.let { add(it) }
            if (isEmpty()) add(suggestion.reason.ifBlank { context.getString(R.string.watch_smart_reason_default) })
        }
        val subtitle = subtitleParts.joinToString(" · ")
        val sourceLabel = when (suggestion.source) {
            "local" -> context.getString(R.string.watch_smart_source_local)
            else -> context.getString(R.string.watch_smart_source_phone)
        }

        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_START)
            .addContent(
                text(sourceLabel, 11, color = COLOR_ON_PRIMARY_DIM, weight = FONT_WEIGHT_MEDIUM),
            )
            .addContent(spacer(2))
            .addContent(
                text(titleText, 18, color = COLOR_ON_PRIMARY, weight = FONT_WEIGHT_BOLD),
            )
            .addContent(spacer(2))
            .addContent(text(subtitle, 12, color = COLOR_ON_PRIMARY_DIM))

        return cardBox(
            context = context,
            background = COLOR_PRIMARY,
            content = column.build(),
            clickable = openRouteAction(
                context,
                routeId = suggestion.routeId,
                routeName = suggestion.routeName.ifBlank { suggestion.routeId },
                description = suggestion.stopName.ifBlank { suggestion.pathName },
                provider = suggestion.provider,
            ),
        )
    }

    private fun favoriteRow(
        context: Context,
        favorite: WearArrivalCard,
    ): LayoutElementBuilders.LayoutElement {
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_START)
            .addContent(text(favorite.routeName, 14, color = COLOR_ON_SURFACE, weight = FONT_WEIGHT_BOLD))
            .addContent(text(favorite.stopName, 11, color = COLOR_ON_SURFACE_DIM))
            .addContent(text(favorite.etaText, 13, color = COLOR_ACCENT, weight = FONT_WEIGHT_BOLD))

        val clickable = if (favorite.routeId.isNotBlank()) {
            openRouteAction(
                context,
                routeId = favorite.routeId,
                routeName = favorite.routeName.ifBlank { favorite.routeId },
                description = favorite.stopName,
                provider = favorite.provider,
            )
        } else {
            launchAppAction(context)
        }

        return cardBox(
            context = context,
            background = COLOR_SURFACE,
            content = column.build(),
            clickable = clickable,
        )
    }

    private fun emptyState(
        context: Context,
        snapshot: WearTileSnapshot,
    ): LayoutElementBuilders.LayoutElement {
        val title = if (snapshot.syncEnabled) {
            context.getString(R.string.watch_state_no_data)
        } else {
            context.getString(R.string.watch_state_sync_disabled)
        }
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_START)
            .addContent(text(title, 13, color = COLOR_ON_SURFACE, weight = FONT_WEIGHT_BOLD))
            .addContent(spacer(2))
            .addContent(
                text(
                    context.getString(R.string.watch_action_open_phone),
                    11,
                    color = COLOR_ON_SURFACE_DIM,
                ),
            )
        return cardBox(
            context = context,
            background = COLOR_SURFACE,
            content = column.build(),
            clickable = launchAppAction(context),
        )
    }

    private fun footerButton(context: Context): LayoutElementBuilders.LayoutElement {
        val label = context.getString(R.string.watch_section_search)
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(text(label, 13, color = COLOR_ON_SECONDARY, weight = FONT_WEIGHT_BOLD))
        return cardBox(
            context = context,
            background = COLOR_SECONDARY,
            content = column.build(),
            clickable = openSearchAction(context),
        )
    }

    private fun cardBox(
        context: Context,
        background: Int,
        content: LayoutElementBuilders.LayoutElement,
        clickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(wrap())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(background))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(18f))
                                    .build(),
                            )
                            .build(),
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(dp(12f))
                            .setEnd(dp(12f))
                            .setTop(dp(8f))
                            .setBottom(dp(8f))
                            .build(),
                    )
                    .setClickable(clickable)
                    .build(),
            )
            .addContent(content)
            .build()
    }

    private fun text(
        value: String,
        sizeSp: Int,
        color: Int,
        weight: Int = LayoutElementBuilders.FONT_WEIGHT_NORMAL,
    ): LayoutElementBuilders.Text {
        return LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setMaxLines(1)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(sizeSp.toFloat()))
                    .setWeight(
                        LayoutElementBuilders.FontWeightProp.Builder()
                            .setValue(weight)
                            .build(),
                    )
                    .setColor(argb(color))
                    .build(),
            )
            .build()
    }

    private fun spacer(heightDp: Int): LayoutElementBuilders.Spacer {
        return LayoutElementBuilders.Spacer.Builder()
            .setHeight(dp(heightDp.toFloat()))
            .build()
    }

    private fun openRouteAction(
        context: Context,
        routeId: String,
        routeName: String,
        description: String,
        provider: String,
    ): ModifiersBuilders.Clickable {
        val encodedName = Uri.encode(routeName.ifBlank { routeId })
        val encodedDesc = Uri.encode(description)
        val deeplinkUri =
            "yabus-wear://route/$routeId?routeName=$encodedName&description=$encodedDesc&provider=$provider"
        val androidActivity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(context.packageName)
            .setClassName(MainActivity::class.java.name)
            .addKeyToExtraMapping(
                "deeplink",
                ActionBuilders.stringExtra(deeplinkUri),
            )
            .build()
        val launchAction = ActionBuilders.LaunchAction.Builder()
            .setAndroidActivity(androidActivity)
            .build()
        return ModifiersBuilders.Clickable.Builder()
            .setId("route_$routeId")
            .setOnClick(launchAction)
            .build()
    }

    private fun openSearchAction(context: Context): ModifiersBuilders.Clickable {
        val androidActivity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(context.packageName)
            .setClassName(MainActivity::class.java.name)
            .addKeyToExtraMapping(
                "deeplink",
                ActionBuilders.stringExtra("yabus-wear://search"),
            )
            .build()
        return ModifiersBuilders.Clickable.Builder()
            .setId("open_search")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(androidActivity)
                    .build(),
            )
            .build()
    }

    private fun launchAppAction(context: Context): ModifiersBuilders.Clickable {
        val androidActivity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(context.packageName)
            .setClassName(MainActivity::class.java.name)
            .build()
        return ModifiersBuilders.Clickable.Builder()
            .setId("open_app")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(androidActivity)
                    .build(),
            )
            .build()
    }

    companion object {
        private const val RESOURCES_VERSION = "1"
        private const val FRESHNESS_INTERVAL_MS = 60_000L
        private const val MAX_FAVORITES = 3
        private const val IMAGE_BUS = "image_bus"

        // Material 3 inspired palette tuned for AMOLED.
        private const val COLOR_PRIMARY = 0xFFFFB870.toInt()
        private const val COLOR_ON_PRIMARY = 0xFF1F1300.toInt()
        private const val COLOR_ON_PRIMARY_DIM = 0xFF4A3300.toInt()
        private const val COLOR_SURFACE = 0xFF1F1F23.toInt()
        private const val COLOR_ON_SURFACE = 0xFFE6E1E5.toInt()
        private const val COLOR_ON_SURFACE_DIM = 0xFFA9A4AC.toInt()
        private const val COLOR_ACCENT = 0xFFF0BB66.toInt()
        private const val COLOR_SECONDARY = 0xFF293040.toInt()
        private const val COLOR_ON_SECONDARY = 0xFFE0E2EC.toInt()

        fun requestUpdate(context: Context) {
            try {
                getUpdater(context.applicationContext)
                    .requestUpdate(YaBusTileService::class.java)
            } catch (_: Throwable) {
                // Tile may not be installed by the user yet; safe to ignore.
            }
        }
    }
}
