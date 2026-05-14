package com.nowbar.api.notification

import android.app.PendingIntent
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Parcelable

class OngoingExtrasBuilder {

    companion object {
        const val KEY_STYLE = "android.ongoingActivityNoti.style"
        const val KEY_CHIP_BG_COLOR = "android.ongoingActivityNoti.chipBgColor"
        const val KEY_CHIP_ICON = "android.ongoingActivityNoti.chipIcon"
        const val KEY_CHIP_EXPANDED_TEXT = "android.ongoingActivityNoti.chipExpandedText"
        const val KEY_PRIMARY_INFO = "android.ongoingActivityNoti.primaryInfo"
        const val KEY_SECONDARY_INFO = "android.ongoingActivityNoti.secondaryInfo"
        const val KEY_NOWBAR_SECONDARY_INFO = "android.ongoingActivityNoti.nowbarSecondaryInfo"
        const val KEY_ACTION_TYPE = "android.ongoingActivityNoti.actionType"
        const val KEY_PROGRESS = "android.ongoingActivityNoti.progress"
        const val KEY_PROGRESS_MAX = "android.ongoingActivityNoti.progressMax"
        const val KEY_PROGRESS_SEGMENTS = "android.ongoingActivityNoti.progressSegments"
        const val KEY_PROGRESS_COLOR = "android.ongoingActivityNoti.progressSegments.progressColor"
        const val KEY_SEGMENT_COLOR = "android.ongoingActivityNoti.progressSegments.segmentColor"
        const val KEY_SEGMENT_START = "android.ongoingActivityNoti.progressSegments.segmentStart"
        const val KEY_SEGMENT_ICON = "android.ongoingActivityNoti.progressSegments.icon"
        const val KEY_SHOW_SMALL_ICON = "android.showSmallIcon"
        const val KEY_NOWBAR_ICON = "android.ongoingActivityNoti.nowbarIcon"
        const val KEY_SECOND_ICON = "android.ongoingActivityNoti.secondIcon"
        const val KEY_NOWBAR_PRIMARY_INFO = "android.ongoingActivityNoti.nowbarPrimaryInfo"
        const val KEY_ACTION_PRIMARY_SET = "android.ongoingActivityNoti.actionPrimarySet"
        const val KEY_CHRONOMETER_REMOTE_VIEW = "android.ongoingActivityNoti.chronometerRemoteView"
        const val KEY_CHRONOMETER_REMOTE_VIEW_TAG = "android.ongoingActivityNoti.chronometerRemoteViewTag"
        const val KEY_CHRONOMETER_REMOTE_VIEW_POSITION = "android.ongoingActivityNoti.chronometerRemoteViewPosition"
        const val KEY_NOWBAR_CHRONOMETER_POSITION = "android.ongoingActivityNoti.nowbarChronometerPosition"
        const val KEY_NOWBAR_PENDING_INTENT_ON_SUB_SCREEN = "android.ongoingActivityNoti.nowbarPendingIntentOnSubScreen"
        const val KEY_SUBST_NAME = "android.substName"
        const val KEY_IS_CAPSULE = "isCapsule"
        const val KEY_CAPSULE_LAYOUT = "capsule_layout"
        const val KEY_CAPSULE_ACTION = "capsule_action"
        const val KEY_CAPSULE_BG_START_COLOR = "bg_startColor"
        const val KEY_CAPSULE_BG_END_COLOR = "bg_endColor"
        const val KEY_CAPSULE_PRIORITY = "capsule_priority"
        const val KEY_ACTION_BG_COLOR = "android.ongoingActivityNoti.actionBgColor"
        const val KEY_FIRST_ICON = "android.ongoingActivityNoti.firstIcon"
        const val KEY_SECONDARY_INFO_ICON = "android.ongoingActivityNoti.secondaryInfoIcon"

        const val STYLE_NOTIFICATION_ONLY = 0
        const val STYLE_BOTH = 1
        const val ACTION_TYPE_BUTTON_TEXT = 1
        const val MAX_PROGRESS = 100
    }

    private var style: Int = STYLE_BOTH
    private var chipConfig: ChipConfig? = null
    private var primaryInfo: String? = null
    private var secondaryInfo: String? = null
    private var nowbarSecondaryInfo: String? = null
    private var actionType: Int = ACTION_TYPE_BUTTON_TEXT
    private var progress: Int? = null
    private var progressMax: Int = MAX_PROGRESS
    private var progressColor: Int? = null
    private var segments: List<ProgressSegment> = emptyList()
    private var showSmallIcon: Boolean = true
    private var nowbarIcon: Icon? = null
    private var secondIcon: Icon? = null
    private var nowbarPrimaryInfo: String? = null
    private var actionPrimarySet: Int = 1
    private var chronometerConfig: ChronometerConfig? = null
    private var capsuleConfig: CapsuleConfig? = null
    private var substName: String? = null
    private var nowBarSubScreenIntent: PendingIntent? = null
    private var actionBgColor: Int? = null
    private var firstIcon: Icon? = null
    private var secondaryInfoIcon: Icon? = null

    fun setStyle(style: Int): OngoingExtrasBuilder = apply {
        this.style = style
    }

    fun setChipConfig(config: ChipConfig): OngoingExtrasBuilder = apply {
        this.chipConfig = config
    }

    fun setPrimaryInfo(text: String): OngoingExtrasBuilder = apply {
        this.primaryInfo = text
    }

    fun setSecondaryInfo(text: String): OngoingExtrasBuilder = apply {
        this.secondaryInfo = text
    }

    fun setNowBarSecondaryInfo(text: String): OngoingExtrasBuilder = apply {
        this.nowbarSecondaryInfo = text
    }

    fun setActionType(type: Int): OngoingExtrasBuilder = apply {
        this.actionType = type
    }

    fun setProgress(current: Int, max: Int = MAX_PROGRESS): OngoingExtrasBuilder = apply {
        require(max > 0) { "Progress max must be positive" }
        this.progress = current.coerceIn(0, max)
        this.progressMax = max
    }

    fun setProgressColor(color: Int): OngoingExtrasBuilder = apply {
        this.progressColor = color
    }

    fun setProgressSegments(segments: List<ProgressSegment>): OngoingExtrasBuilder = apply {
        segments.forEach { segment ->
            require(segment.startPosition in 0f..1f) { "Segment startPosition must be in [0.0, 1.0]" }
        }
        this.segments = segments
    }

    fun setShowSmallIcon(show: Boolean): OngoingExtrasBuilder = apply {
        this.showSmallIcon = show
    }

    fun setNowBarIcon(icon: Icon): OngoingExtrasBuilder = apply {
        this.nowbarIcon = icon
    }

    fun setSecondIcon(icon: Icon): OngoingExtrasBuilder = apply {
        this.secondIcon = icon
    }

    fun setNowBarPrimaryInfo(text: String): OngoingExtrasBuilder = apply {
        this.nowbarPrimaryInfo = text
    }

    fun setActionPrimarySet(value: Int): OngoingExtrasBuilder = apply {
        this.actionPrimarySet = value
    }

    fun setChronometerConfig(config: ChronometerConfig): OngoingExtrasBuilder = apply {
        this.chronometerConfig = config
    }

    fun setCapsuleConfig(config: CapsuleConfig): OngoingExtrasBuilder = apply {
        this.capsuleConfig = config
    }

    fun setSubstName(name: String): OngoingExtrasBuilder = apply {
        this.substName = name
    }

    fun setNowBarSubScreenIntent(intent: PendingIntent): OngoingExtrasBuilder = apply {
        this.nowBarSubScreenIntent = intent
    }

    fun setActionBgColor(color: Int): OngoingExtrasBuilder = apply {
        this.actionBgColor = color
    }

    fun setFirstIcon(icon: Icon): OngoingExtrasBuilder = apply {
        this.firstIcon = icon
    }

    fun setSecondaryInfoIcon(icon: Icon): OngoingExtrasBuilder = apply {
        this.secondaryInfoIcon = icon
    }

    fun build(): Bundle {
        val bundle = Bundle()

        bundle.putInt(KEY_STYLE, style)
        bundle.putInt(KEY_ACTION_TYPE, actionType)
        bundle.putBoolean(KEY_SHOW_SMALL_ICON, showSmallIcon)

        chipConfig?.let { chip ->
            chip.icon?.let { bundle.putParcelable(KEY_CHIP_ICON, it) }
            chip.backgroundColor?.let { bundle.putInt(KEY_CHIP_BG_COLOR, it) }
            chip.expandedText?.let { bundle.putString(KEY_CHIP_EXPANDED_TEXT, it) }
        }

        primaryInfo?.let { bundle.putString(KEY_PRIMARY_INFO, it) }
        secondaryInfo?.let { bundle.putString(KEY_SECONDARY_INFO, it) }
        nowbarSecondaryInfo?.let { bundle.putString(KEY_NOWBAR_SECONDARY_INFO, it) }

        progress?.let { current ->
            bundle.putInt(KEY_PROGRESS, current)
            bundle.putInt(KEY_PROGRESS_MAX, progressMax)
        }

        progressColor?.let { bundle.putInt(KEY_PROGRESS_COLOR, it) }
        nowbarIcon?.let { bundle.putParcelable(KEY_NOWBAR_ICON, it) }
        secondIcon?.let { bundle.putParcelable(KEY_SECOND_ICON, it) }
        nowbarPrimaryInfo?.let { bundle.putString(KEY_NOWBAR_PRIMARY_INFO, it) }

        if (segments.isNotEmpty()) {
            val segmentBundles = segments.map { segment ->
                Bundle().apply {
                    putInt(KEY_SEGMENT_COLOR, segment.color)
                    putFloat(KEY_SEGMENT_START, segment.startPosition)
                    segment.icon?.let { putParcelable(KEY_SEGMENT_ICON, it) }
                }
            }.toTypedArray<Parcelable>()

            bundle.putParcelableArray(KEY_PROGRESS_SEGMENTS, segmentBundles)
        }

        bundle.putInt(KEY_ACTION_PRIMARY_SET, actionPrimarySet)

        chronometerConfig?.let { config ->
            bundle.putParcelable(KEY_CHRONOMETER_REMOTE_VIEW, config.remoteView)
            bundle.putCharSequence(KEY_CHRONOMETER_REMOTE_VIEW_TAG, config.tag)
            bundle.putInt(KEY_CHRONOMETER_REMOTE_VIEW_POSITION, config.viewPosition)
            bundle.putInt(KEY_NOWBAR_CHRONOMETER_POSITION, config.nowBarPosition)
        }

        capsuleConfig?.let { config ->
            bundle.putBoolean(KEY_IS_CAPSULE, true)
            bundle.putParcelable(KEY_CAPSULE_LAYOUT, config.layout)
            bundle.putParcelable(KEY_CAPSULE_ACTION, config.action)
            bundle.putInt(KEY_CAPSULE_BG_START_COLOR, config.bgStartColor)
            bundle.putInt(KEY_CAPSULE_BG_END_COLOR, config.bgEndColor)
            config.priority?.let { bundle.putString(KEY_CAPSULE_PRIORITY, it) }
        }

        substName?.let { bundle.putCharSequence(KEY_SUBST_NAME, it) }
        nowBarSubScreenIntent?.let { bundle.putParcelable(KEY_NOWBAR_PENDING_INTENT_ON_SUB_SCREEN, it) }

        actionBgColor?.let { bundle.putInt(KEY_ACTION_BG_COLOR, it) }
        firstIcon?.let { bundle.putParcelable(KEY_FIRST_ICON, it) }
        secondaryInfoIcon?.let { bundle.putParcelable(KEY_SECONDARY_INFO_ICON, it) }

        return bundle
    }
}