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
import io.github.d4viddf.hyperisland_kit.models.TimerInfo

object TripMonitorEnhancedSurfaceSupport {
    private const val HYPER_PICTURE_BUS = "trip_monitor_bus"
    private const val HYPER_PICTURE_FLAG = "trip_monitor_flag"
    private const val HYPER_PROGRESS_TRACK_COLOR = "#335A6B7A"
    private const val HYPER_ACTION_OPEN_ROUTE = "open_trip_route"
    private const val HYPER_ACTION_PAUSE = "pause_trip_monitor"
    private const val HYPER_ACTION_MARK_BOARDED = "mark_trip_boarded"
    private const val HYPER_ACTION_NOT_BOARDED = "mark_trip_not_boarded"
    private const val HYPER_STATUS_MAX_LENGTH = 16
    private const val HYPER_ROUTE_TITLE_MAX_LENGTH = 22
    private const val HYPER_ROUTE_DETAIL_MAX_LENGTH = 24
    private const val HYPER_BASE_CONTENT_MAX_LENGTH = 24
    private const val HYPER_PROMPT_EXPANDED_TIME_MS = 8_000
    private const val HYPER_IMMINENT_EXPANDED_TIME_MS = 2_800
    private const val HYPER_IMMINENT_THRESHOLD_MS = 60_000L
    private const val HYPER_ESTIMATED_IMMINENT_COUNTDOWN_MS = 45_000L
    private const val STATUS_PREFIX = "\u9084\u6709"
    private const val STATUS_SUFFIX = "\u5230\u7ad9"
    private const val STOPS_SUFFIX = "\u7ad9"
    private const val ARRIVING_TEXT = "\u9032\u7ad9"
    private const val IMMINENT_STATUS_TEXT = "\u5373\u5c07\u9032\u7ad9"
    private const val ETA_ESTIMATE_LABEL = "\u9810\u4f30"
    private const val BOARDING_PROMPT_TITLE = "\u6709\u4e0a\u8eca\u55ce\uff1f"
    private const val MARK_BOARDED_TEXT = "\u6211\u5df2\u4e0a\u8eca"
    private const val NOT_BOARDED_TEXT = "\u9084\u6c92\u4e0a\u8eca"
    private const val PAUSE_TEXT = "\u66ab\u505c"
    private const val SEPARATOR = " \u2022 "
    private val ETA_COUNTDOWN_REGEX = Regex("^([0-9]{1,2}):([0-9]{2})$")

    fun apply(
        context: Context,
        notification: Notification,
        session: TrackingSession,
        snapshot: TrackingSnapshot,
        contentIntent: PendingIntent,
        stopIntent: PendingIntent,
        markBoardedIntent: PendingIntent? = null,
        notBoardedIntent: PendingIntent? = null,
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
                    contentIntent = contentIntent,
                    stopIntent = stopIntent,
                    markBoardedIntent = markBoardedIntent,
                    notBoardedIntent = notBoardedIntent,
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
        contentIntent: PendingIntent,
        stopIntent: PendingIntent,
        markBoardedIntent: PendingIntent?,
        notBoardedIntent: PendingIntent?,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        if (!HyperIslandNotification.isSupported(context)) {
            return
        }

        val accentColor = resolveAccentColor(snapshot)
        val accentHex = toHexColor(accentColor)
        val icon = HyperPicture(HYPER_PICTURE_BUS, context, R.drawable.ic_status_bus)
        val flagIcon = HyperPicture(HYPER_PICTURE_FLAG, context, R.drawable.ic_progress_flag)
        val progressPercent = deriveProgressPercent(snapshot)
        val hyperStatus = buildHyperIslandStatus(snapshot)
        val routeTitle = compactText(session.routeName.ifBlank { snapshot.title }, HYPER_ROUTE_TITLE_MAX_LENGTH)
        val routeDetail = buildHyperIslandRouteDetail(session, snapshot)
        val openAction = HyperAction(
            key = HYPER_ACTION_OPEN_ROUTE,
            title = "Open",
            pendingIntent = contentIntent,
            actionIntentType = 1,
        )
        val pauseAction = HyperAction(
            key = HYPER_ACTION_PAUSE,
            title = PAUSE_TEXT,
            pendingIntent = stopIntent,
            actionIntentType = 3,
            bgColor = "#FFCC3344",
            titleColor = "#FFFFFFFF",
        )
        val boardedAction = markBoardedIntent?.let { intent ->
            HyperAction(
                key = HYPER_ACTION_MARK_BOARDED,
                title = MARK_BOARDED_TEXT,
                pendingIntent = intent,
                actionIntentType = 3,
                bgColor = "#FF2E7D32",
                titleColor = "#FFFFFFFF",
            )
        }
        val notBoardedAction = notBoardedIntent?.let { intent ->
            HyperAction(
                key = HYPER_ACTION_NOT_BOARDED,
                title = NOT_BOARDED_TEXT,
                pendingIntent = intent,
                actionIntentType = 3,
                bgColor = "#FF455A64",
                titleColor = "#FFFFFFFF",
            )
        }
        val showBoardingPrompt =
            snapshot.boardingPromptEligible && boardedAction != null && notBoardedAction != null
        val shouldAutoExpand = showBoardingPrompt || hyperStatus.showImminentState
        val expandedTimeMs = when {
            showBoardingPrompt -> HYPER_PROMPT_EXPANDED_TIME_MS
            hyperStatus.showImminentState -> HYPER_IMMINENT_EXPANDED_TIME_MS
            else -> null
        }

        val builder = HyperIslandNotification.Builder(
            context,
            "trip_monitor_${session.routeKey}_${session.pathId}",
            snapshot.title.ifBlank { session.routeName },
        )
            .setLogEnabled(false)
            .setEnableFloat(false)
            .setIslandFirstFloat(shouldAutoExpand)
            .setIslandConfig(
                priority = 1,
                dismissible = false,
                maxSize = shouldAutoExpand,
                highlightColor = accentHex.takeIf { hyperStatus.showImminentState },
                expandedTimeMs = expandedTimeMs,
                needCloseAnimation = shouldAutoExpand,
            )
            .addPicture(icon)
            .addHiddenAction(openAction)
            .setBaseInfo(
                title = routeTitle,
                content = compactText(hyperStatus.statusText, HYPER_BASE_CONTENT_MAX_LENGTH),
                subContent = routeDetail?.let { compactText(it, HYPER_ROUTE_DETAIL_MAX_LENGTH) },
                pictureKey = HYPER_PICTURE_BUS,
                colorContent = accentHex,
                colorContentDark = accentHex,
                actionKeys = listOf(openAction.key),
            )

        if (hyperStatus.countdownTargetTimeMs != null) {
            builder
                .setScene("timer")
                .setHintTimer(
                    frontText1 = ETA_ESTIMATE_LABEL,
                    mainText1 = IMMINENT_STATUS_TEXT,
                    timer = buildHyperCountdownTimerInfo(hyperStatus.countdownTargetTimeMs),
                    action = openAction,
                )
        }

        if (showBoardingPrompt) {
            builder
                .addHiddenAction(boardedAction!!)
                .addHiddenAction(notBoardedAction!!)
                .setHintInfo(BOARDING_PROMPT_TITLE)
                .setTextButtons(boardedAction, notBoardedAction)
        } else {
            builder
                .addHiddenAction(pauseAction)
                .setTextButtons(pauseAction)
        }

        val statusTextInfo = TextInfo(
            title = compactText(hyperStatus.statusText, HYPER_STATUS_MAX_LENGTH),
            content = null,
            showHighlightColor = hyperStatus.showImminentState,
            narrowFont = true,
        )
        val leftInfo = ImageTextInfoLeft(
            type = 1,
            picInfo = PicInfo(type = 1, pic = HYPER_PICTURE_BUS),
            textInfo = TextInfo(
                title = routeTitle,
                content = routeDetail?.let { compactText(it, HYPER_ROUTE_DETAIL_MAX_LENGTH) },
            ),
        )

        if (progressPercent != null) {
            builder
                .addPicture(flagIcon)
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
                    left = leftInfo,
                    progressText = ProgressTextInfo(
                        progressInfo = CircularProgressInfo(
                            progress = progressPercent,
                            colorReach = accentHex,
                            colorUnReach = HYPER_PROGRESS_TRACK_COLOR,
                        ),
                        textInfo = statusTextInfo,
                    ),
                )
        } else {
            builder
                .setSmallIsland(HYPER_PICTURE_BUS)
                .setBigIslandInfo(
                    left = leftInfo,
                    centerText = statusTextInfo,
                )
        }

        notification.extras.putAll(builder.buildResourceBundle())
        notification.extras.putString("miui.focus.param", builder.buildJsonParam())
    }

    private fun buildCompactStatusText(snapshot: TrackingSnapshot): String {
        normalizeShortCriticalText(snapshot.shortCriticalText)?.let {
            return compactText(it, HYPER_STATUS_MAX_LENGTH)
        }

        val stops = resolveTrackedStops(snapshot)
        val etaText = resolveTrackedEtaText(snapshot)

        if (etaText != null && stops != null && stops > 0) {
            return compactText("$stops$STOPS_SUFFIX|$etaText", HYPER_STATUS_MAX_LENGTH)
        }
        if (etaText != null) {
            return compactText(etaText, HYPER_STATUS_MAX_LENGTH)
        }
        if (stops != null) {
            return compactText(if (stops <= 0) ARRIVING_TEXT else "$stops$STOPS_SUFFIX", HYPER_STATUS_MAX_LENGTH)
        }
        return compactText(snapshot.content.ifBlank { snapshot.title }, HYPER_STATUS_MAX_LENGTH)
    }

    private fun buildPrimarySurfaceText(snapshot: TrackingSnapshot): String {
        val stops = resolveTrackedStops(snapshot)
        val etaText = resolveTrackedEtaText(snapshot)

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

    private fun buildHyperIslandRouteDetail(
        session: TrackingSession,
        snapshot: TrackingSnapshot,
    ): String? {
        return session.pathName.trim().takeIf { it.isNotEmpty() }
            ?: snapshot.subText.trim().takeIf { it.isNotEmpty() && !it.contains(session.routeName) }
    }

    private fun buildHyperIslandStatus(snapshot: TrackingSnapshot): HyperIslandStatus {
        val stops = resolveTrackedStops(snapshot)
        val etaText = resolveTrackedEtaText(snapshot)
        val countdownTargetTimeMs = resolveHyperCountdownTargetTimeMs(snapshot, etaText)
        val showImminentState = countdownTargetTimeMs != null || isImmediateEtaText(etaText)
        val statusText = when {
            showImminentState -> IMMINENT_STATUS_TEXT
            etaText != null && stops != null && stops > 0 && isDurationLikeEta(etaText) ->
                compactText("$etaText|$stops$STOPS_SUFFIX", HYPER_STATUS_MAX_LENGTH)

            etaText != null -> compactText(etaText, HYPER_STATUS_MAX_LENGTH)
            stops != null && stops > 0 -> compactText("$stops$STOPS_SUFFIX", HYPER_STATUS_MAX_LENGTH)
            stops != null -> ARRIVING_TEXT
            else -> compactText(snapshot.content.ifBlank { snapshot.title }, HYPER_STATUS_MAX_LENGTH)
        }
        return HyperIslandStatus(
            statusText = statusText,
            countdownTargetTimeMs = countdownTargetTimeMs,
            showImminentState = showImminentState,
        )
    }

    private fun resolveHyperCountdownTargetTimeMs(
        snapshot: TrackingSnapshot,
        etaText: String?,
    ): Long? {
        val now = System.currentTimeMillis()
        if (!snapshot.hasBoarded) {
            snapshot.boardingEtaSeconds
                ?.takeIf { it in 1 until 60 }
                ?.let { return now + (it * 1_000L) }
        }

        val explicitDurationMs = parseEtaDurationMillis(etaText)
        if (explicitDurationMs != null && explicitDurationMs in 1 until HYPER_IMMINENT_THRESHOLD_MS) {
            return now + explicitDurationMs
        }
        if (isImmediateEtaText(etaText)) {
            return now + HYPER_ESTIMATED_IMMINENT_COUNTDOWN_MS
        }
        return null
    }

    private fun buildHyperCountdownTimerInfo(targetTimeMs: Long): TimerInfo {
        val now = System.currentTimeMillis()
        return TimerInfo(
            timerType = -1,
            timerWhen = targetTimeMs,
            timerTotal = now,
            timerSystemCurrent = now,
        )
    }

    private fun resolveTrackedStops(snapshot: TrackingSnapshot): Int? {
        return if (snapshot.hasBoarded) snapshot.remainingStops else snapshot.boardingStopsAway
    }

    private fun resolveTrackedEtaText(snapshot: TrackingSnapshot): String? {
        return if (snapshot.hasBoarded) {
            extractEtaFromShortCritical(snapshot.shortCriticalText)
        } else {
            normalizeEtaText(snapshot.boardingEtaText)
                ?: extractEtaFromShortCritical(snapshot.shortCriticalText)
        }
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
        return shortCriticalText
            ?.replace('\u2022', '|')
            ?.replace('\u00B7', '|')
            ?.replace('\uFF5C', '|')
            ?.trim()
            ?.takeIf { it.isNotEmpty() && it != "--" }
    }

    private fun normalizeEtaText(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed == "--") {
            return null
        }
        return trimmed
    }

    private fun parseEtaDurationMillis(etaText: String?): Long? {
        val normalized = normalizeEtaText(etaText)?.replace("(", "")?.replace(")", "") ?: return null
        val match = ETA_COUNTDOWN_REGEX.matchEntire(normalized) ?: return null
        val minutes = match.groupValues[1].toLongOrNull() ?: return null
        val seconds = match.groupValues[2].toLongOrNull() ?: return null
        return ((minutes * 60L) + seconds) * 1_000L
    }

    private fun looksLikeStopCount(value: String): Boolean {
        val normalized = value.replace(" ", "")
        return normalized.matches(Regex("^[0-9]+$STOPS_SUFFIX$"))
    }

    private fun isImmediateEtaText(value: String?): Boolean {
        val normalized = normalizeEtaText(value)?.replace(" ", "") ?: return false
        return normalized.startsWith("<1") ||
            normalized.contains("\u9032\u7ad9") ||
            normalized.contains("\u5373\u5c07")
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

    private data class HyperIslandStatus(
        val statusText: String,
        val countdownTargetTimeMs: Long?,
        val showImminentState: Boolean,
    )
}
