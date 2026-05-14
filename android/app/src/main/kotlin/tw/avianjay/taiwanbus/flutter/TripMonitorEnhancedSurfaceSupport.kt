package tw.avianjay.taiwanbus.flutter

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.graphics.Color
import android.os.Build
import androidx.core.graphics.drawable.IconCompat
import com.nowbar.api.FeatureDetector
import com.nowbar.api.cards.CustomCard
import com.nowbar.api.notification.ChipConfig
import com.nowbar.api.notification.OngoingExtrasBuilder
import io.github.d4viddf.hyperisland_kit.HyperAction
import io.github.d4viddf.hyperisland_kit.HyperIslandNotification
import io.github.d4viddf.hyperisland_kit.HyperPicture
import io.github.d4viddf.hyperisland_kit.models.CircularProgressInfo
import io.github.d4viddf.hyperisland_kit.models.ImageTextInfoLeft
import io.github.d4viddf.hyperisland_kit.models.PicInfo
import io.github.d4viddf.hyperisland_kit.models.ProgressTextInfo
import io.github.d4viddf.hyperisland_kit.models.TextInfo

object TripMonitorEnhancedSurfaceSupport {
    private const val HYPER_PICTURE_BUS = "trip_monitor_bus"
    private const val HYPER_PICTURE_FLAG = "trip_monitor_flag"
    private const val HYPER_PROGRESS_TRACK_COLOR = "#335A6B7A"

    fun apply(
        context: Context,
        notification: Notification,
        session: TrackingSession,
        snapshot: TrackingSnapshot,
        contentIntent: PendingIntent,
        stopIntent: PendingIntent,
    ): Notification {
        runCatching {
            applySamsungNowBar(
                context = context,
                notification = notification,
                session = session,
                snapshot = snapshot,
                contentIntent = contentIntent,
            )
        }
        runCatching {
            applyHyperIsland(
                context = context,
                notification = notification,
                session = session,
                snapshot = snapshot,
                stopIntent = stopIntent,
            )
        }
        return notification
    }

    private fun applySamsungNowBar(
        context: Context,
        notification: Notification,
        session: TrackingSession,
        snapshot: TrackingSnapshot,
        contentIntent: PendingIntent,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        if (!FeatureDetector.isSamsungNowBarSupported(context)) {
            return
        }

        val accentColor = resolveAccentColor(snapshot)
        val chipText = buildShortStatusText(snapshot)
        val icon = IconCompat.createWithResource(context, R.drawable.ic_status_bus)
        val flagIcon = IconCompat.createWithResource(context, R.drawable.ic_progress_flag)
        val progressPercent = deriveProgressPercent(snapshot)
        val secondaryText = buildSecondarySurfaceText(session, snapshot)
        val nowBarText = buildNowBarDetailText(session, snapshot)

        val cardBuilder = CustomCard.Builder
            .create(
                snapshot.title.ifBlank { session.routeName },
                icon,
                snapshot.title.ifBlank { session.routeName },
            )
            .accentColor(accentColor)
            .tapAction(contentIntent)
            .secondaryText(secondaryText)
            .chipText(chipText)
            .nowBarText(nowBarText)
            .firstIcon(icon)
            .subScreenIntent(contentIntent)

        if (progressPercent != null) {
            cardBuilder
                .progressValue(progressPercent)
                .progressMax(100)
                .customProgressColor(accentColor)
                .secondaryInfoIcon(flagIcon)
        }

        val card = cardBuilder.build()
        val extras = OngoingExtrasBuilder()
            .setStyle(OngoingExtrasBuilder.STYLE_BOTH)
            .setActionType(OngoingExtrasBuilder.ACTION_TYPE_BUTTON_TEXT)
            .setShowSmallIcon(true)
            .setChipConfig(
                ChipConfig(
                    icon = icon.toIcon(context),
                    backgroundColor = accentColor,
                    expandedText = chipText,
                ),
            )
            .setPrimaryInfo(card.toPrimaryInfo())
            .setSecondaryInfo(card.toSecondaryInfo())
            .setNowBarSecondaryInfo(card.toNowBarSecondaryInfo() ?: secondaryText)
            .setNowBarPrimaryInfo(card.toNowBarPrimaryInfo() ?: card.toPrimaryInfo())
            .setNowBarIcon(icon.toIcon(context))
            .setFirstIcon(icon.toIcon(context))
            .setActionPrimarySet(card.toActionPrimarySet())
            .setActionBgColor(accentColor)
            .setSubstName(card.toSubstName() ?: snapshot.title)
            .setNowBarSubScreenIntent(contentIntent)

        if (progressPercent != null) {
            extras
                .setProgress(progressPercent, 100)
                .setProgressColor(accentColor)
                .setSecondaryInfoIcon(flagIcon.toIcon(context))
        }

        notification.extras.putAll(extras.build())
    }

    private fun applyHyperIsland(
        context: Context,
        notification: Notification,
        session: TrackingSession,
        snapshot: TrackingSnapshot,
        stopIntent: PendingIntent,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        if (!HyperIslandNotification.isSupported(context)) {
            return
        }

        val accentColor = resolveAccentColor(snapshot)
        val accentHex = toHexColor(accentColor)
        val shortStatus = buildShortStatusText(snapshot)
        val detailText = buildSecondarySurfaceText(session, snapshot)
        val progressPercent = deriveProgressPercent(snapshot)
        val pauseAction = HyperAction(
            key = "pause_trip_monitor",
            title = "Pause",
            pendingIntent = stopIntent,
            actionIntentType = 3,
            bgColor = "#FFCC3344",
            titleColor = "#FFFFFFFF",
        )

        val builder = HyperIslandNotification.Builder(
            context,
            "trip_monitor_${session.routeKey}_${session.pathId}",
            snapshot.title.ifBlank { session.routeName },
        )
            .setLogEnabled(false)
            .setEnableFloat(false)
            .setIslandFirstFloat(false)
            .setIslandConfig(priority = 1, dismissible = false, needCloseAnimation = false)
            .setBaseInfo(
                title = compactText(snapshot.title.ifBlank { session.routeName }, 32),
                content = compactText(snapshot.content.ifBlank { detailText }, 42),
                subTitle = session.pathName.trim().takeIf { it.isNotEmpty() }?.let { compactText(it, 20) },
                subContent = detailText.takeIf { it.isNotBlank() }?.let { compactText(it, 28) },
                pictureKey = HYPER_PICTURE_BUS,
            )
            .setTextButtons(pauseAction)
            .addPicture(HyperPicture(HYPER_PICTURE_BUS, context, R.drawable.ic_status_bus))

        if (progressPercent != null) {
            builder
                .addPicture(HyperPicture(HYPER_PICTURE_FLAG, context, R.drawable.ic_progress_flag))
                .setProgressBar(
                    progress = progressPercent,
                    color = accentHex,
                    picForwardKey = HYPER_PICTURE_BUS,
                    picEndKey = HYPER_PICTURE_FLAG,
                )
                .setSmallIslandCircularProgress(
                    pictureKey = HYPER_PICTURE_BUS,
                    progress = progressPercent,
                    color = accentHex,
                    colorUnReach = HYPER_PROGRESS_TRACK_COLOR,
                )
                .setBigIslandInfo(
                    left = ImageTextInfoLeft(
                        type = 1,
                        picInfo = PicInfo(type = 1, pic = HYPER_PICTURE_BUS),
                        textInfo = TextInfo(
                            title = compactText(snapshot.title.ifBlank { session.routeName }, 22),
                            content = compactText(snapshot.content.ifBlank { detailText }, 24),
                        ),
                    ),
                    progressText = ProgressTextInfo(
                        progressInfo = CircularProgressInfo(
                            progress = progressPercent,
                            colorReach = accentHex,
                            colorUnReach = HYPER_PROGRESS_TRACK_COLOR,
                        ),
                        textInfo = TextInfo(
                            title = compactText(shortStatus, 16),
                            content = detailText.takeIf { it.isNotBlank() }?.let { compactText(it, 20) },
                        ),
                    ),
                )
        } else {
            builder
                .setSmallIsland(HYPER_PICTURE_BUS)
                .setBigIslandInfo(
                    left = ImageTextInfoLeft(
                        type = 1,
                        picInfo = PicInfo(type = 1, pic = HYPER_PICTURE_BUS),
                        textInfo = TextInfo(
                            title = compactText(snapshot.title.ifBlank { session.routeName }, 22),
                            content = compactText(snapshot.content.ifBlank { detailText }, 24),
                        ),
                    ),
                    centerText = TextInfo(
                        title = compactText(shortStatus, 16),
                        content = detailText.takeIf { it.isNotBlank() }?.let { compactText(it, 20) },
                    ),
                )
        }

        notification.extras.putAll(builder.buildResourceBundle())
        notification.extras.putString("miui.focus.param", builder.buildJsonParam())
    }

    private fun buildShortStatusText(snapshot: TrackingSnapshot): String {
        val preferred = snapshot.shortCriticalText
            ?.replace('|', ' ')
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        return compactText(preferred ?: snapshot.content.ifBlank { snapshot.title }, 18)
    }

    private fun buildSecondarySurfaceText(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): String {
        val parts = linkedSetOf<String>()
        snapshot.content.trim().takeIf { it.isNotEmpty() }?.let(parts::add)
        snapshot.subText.trim().takeIf { it.isNotEmpty() }?.let(parts::add)
        session.pathName.trim().takeIf { it.isNotEmpty() }?.let(parts::add)
        return compactText(parts.joinToString(" • "), 48)
    }

    private fun buildNowBarDetailText(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): String {
        val parts = linkedSetOf<String>()
        session.pathName.trim().takeIf { it.isNotEmpty() }?.let(parts::add)
        snapshot.subText.trim().takeIf { it.isNotEmpty() }?.let(parts::add)
        return compactText(parts.firstOrNull() ?: snapshot.content.ifBlank { session.routeName }, 28)
    }

    private fun deriveProgressPercent(snapshot: TrackingSnapshot): Int? {
        val progressMax = snapshot.progressMax ?: return null
        val progressValue = snapshot.progressValue ?: return null
        if (progressMax <= 0) {
            return null
        }
        return ((progressValue.toDouble() / progressMax.toDouble()) * 100.0)
            .toInt()
            .coerceIn(0, 100)
    }

    private fun resolveAccentColor(snapshot: TrackingSnapshot): Int {
        return when {
            snapshot.passedDestinationByStops != null -> Color.parseColor("#C62828")
            snapshot.hasBoarded -> Color.parseColor("#2E7D32")
            snapshot.boardingStopsAway != null && snapshot.boardingStopsAway <= 1 ->
                Color.parseColor("#EF6C00")
            else -> Color.parseColor("#1565C0")
        }
    }

    private fun toHexColor(color: Int): String {
        return String.format("#%08X", color)
    }

    private fun compactText(value: String, maxLength: Int): String {
        val normalized = value.replace('\n', ' ').replace(Regex("\\s+"), " ").trim()
        if (normalized.length <= maxLength) {
            return normalized
        }
        return normalized.take(maxLength - 1).trimEnd() + "…"
    }
}
