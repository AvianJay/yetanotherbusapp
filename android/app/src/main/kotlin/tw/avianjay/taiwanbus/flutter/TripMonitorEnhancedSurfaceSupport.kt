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
    private const val STATUS_PREFIX = "\u9084\u6709"
    private const val STATUS_SUFFIX = "\u5230\u7ad9"
    private const val STOPS_SUFFIX = "\u7ad9"
    private const val ARRIVING_TEXT = "\u9032\u7ad9"
    private const val SEPARATOR = " \u2022 "

    fun apply(
        context: Context,
        notification: Notification,
        session: TrackingSession,
        snapshot: TrackingSnapshot,
        contentIntent: PendingIntent,
        stopIntent: PendingIntent,
        includeHyperIsland: Boolean = true,
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
        if (includeHyperIsland) {
            runCatching {
                applyHyperIsland(
                    context = context,
                    notification = notification,
                    session = session,
                    snapshot = snapshot,
                    stopIntent = stopIntent,
                )
            }
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
        val chipText = buildCompactStatusText(snapshot)
        val primaryText = buildPrimarySurfaceText(snapshot)
        val secondaryText = buildSecondarySurfaceText(session, snapshot)
        val icon = IconCompat.createWithResource(context, R.drawable.ic_status_bus)
        val flagIcon = IconCompat.createWithResource(context, R.drawable.ic_progress_flag)
        val progressPercent = deriveProgressPercent(snapshot)

        val cardBuilder = CustomCard.Builder
            .create(
                snapshot.title.ifBlank { session.routeName },
                icon,
                primaryText,
            )
            .accentColor(accentColor)
            .tapAction(contentIntent)
            .secondaryText(secondaryText)
            .chipText(chipText)
            .nowBarText(secondaryText)
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
        val shortStatus = buildCompactStatusText(snapshot)
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
                            content = detailText.takeIf { it.isNotBlank() }?.let {
                                compactText(it, 20)
                            },
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
                        content = detailText.takeIf { it.isNotBlank() }?.let {
                            compactText(it, 20)
                        },
                    ),
                )
        }

        notification.extras.putAll(builder.buildResourceBundle())
        notification.extras.putString("miui.focus.param", builder.buildJsonParam())
    }

    private fun buildCompactStatusText(snapshot: TrackingSnapshot): String {
        normalizeShortCriticalText(snapshot.shortCriticalText)?.let {
            return compactText(it, 16)
        }

        val stops = if (snapshot.hasBoarded) snapshot.remainingStops else snapshot.boardingStopsAway
        val etaText = if (snapshot.hasBoarded) {
            extractEtaFromShortCritical(snapshot.shortCriticalText)
        } else {
            normalizeEtaText(snapshot.boardingEtaText)
                ?: extractEtaFromShortCritical(snapshot.shortCriticalText)
        }

        if (etaText != null && stops != null && stops > 0) {
            return compactText("$stops$STOPS_SUFFIX|$etaText", 16)
        }
        if (etaText != null) {
            return compactText(etaText, 16)
        }
        if (stops != null) {
            return compactText(if (stops <= 0) ARRIVING_TEXT else "$stops$STOPS_SUFFIX", 16)
        }
        return compactText(snapshot.content.ifBlank { snapshot.title }, 16)
    }

    private fun buildPrimarySurfaceText(snapshot: TrackingSnapshot): String {
        val stops = if (snapshot.hasBoarded) snapshot.remainingStops else snapshot.boardingStopsAway
        val etaText = if (snapshot.hasBoarded) {
            extractEtaFromShortCritical(snapshot.shortCriticalText)
        } else {
            normalizeEtaText(snapshot.boardingEtaText)
                ?: extractEtaFromShortCritical(snapshot.shortCriticalText)
        }

        if (etaText != null && isDurationLikeEta(etaText)) {
            val parts = mutableListOf("$STATUS_PREFIX $etaText $STATUS_SUFFIX")
            stops?.let { parts += "$it $STOPS_SUFFIX" }
            return compactText(parts.joinToString(SEPARATOR), 32)
        }
        if (etaText != null) {
            return compactText(etaText, 32)
        }
        if (stops != null) {
            return compactText("$STATUS_PREFIX $stops $STOPS_SUFFIX", 32)
        }
        return compactText(snapshot.content.ifBlank { snapshot.title }, 32)
    }

    private fun buildSecondarySurfaceText(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): String {
        val stopName = inferDisplayStopName(session, snapshot)
        return compactText(
            listOfNotNull(
                stopName?.takeIf { it.isNotBlank() },
                session.routeName.trim().takeIf { it.isNotEmpty() },
            ).joinToString(SEPARATOR).ifBlank {
                snapshot.title.ifBlank { session.routeName }
            },
            48,
        )
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

    private fun inferDisplayStopName(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): String? {
        return snapshot.destinationName?.takeIf { it.isNotBlank() }
            ?: snapshot.boardingName?.takeIf { it.isNotBlank() }
            ?: session.destinationStopName?.takeIf { it.isNotBlank() }
            ?: session.boardingStopName?.takeIf { it.isNotBlank() }
            ?: session.stops.firstOrNull { stop ->
                snapshot.content.contains(stop.stopName) || snapshot.subText.contains(stop.stopName)
            }?.stopName
    }

    private fun extractEtaFromShortCritical(shortCriticalText: String?): String? {
        val normalized = normalizeShortCriticalText(shortCriticalText) ?: return null
        val parts = normalized.split('|').map { it.trim() }.filter { it.isNotEmpty() }
        if (parts.isEmpty()) {
            return null
        }
        return parts.firstOrNull { !looksLikeStopCount(it) }
            ?.let(::normalizeEtaText)
            ?: normalizeEtaText(normalized.takeUnless(::looksLikeStopCount))
    }

    private fun normalizeShortCriticalText(shortCriticalText: String?): String? {
        val normalized = shortCriticalText
            ?.replace('\u2022', '|')
            ?.replace('\u00B7', '|')
            ?.trim()
            ?.takeIf { it.isNotEmpty() && it != "--" }
            ?: return null
        return normalized
    }

    private fun normalizeEtaText(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed == "--") {
            return null
        }
        return trimmed
    }

    private fun looksLikeStopCount(value: String): Boolean {
        val normalized = value.replace(" ", "")
        return normalized.matches(Regex("^[0-9]+$STOPS_SUFFIX$"))
    }

    private fun isDurationLikeEta(value: String): Boolean {
        val normalized = value.replace(" ", "")
        return normalized.startsWith("<") ||
            normalized.contains(':') ||
            normalized.any(Char::isDigit)
    }

    private fun compactText(value: String, maxLength: Int): String {
        val normalized = value.replace('\n', ' ').replace(Regex("\\s+"), " ").trim()
        if (normalized.length <= maxLength) {
            return normalized
        }
        return normalized.take(maxLength - 3).trimEnd() + "..."
    }
}
