package com.nowbar.api.cards

import android.app.PendingIntent
import androidx.core.graphics.drawable.IconCompat

enum class CardType {
    TIMER, MEDIA, NAVIGATION, WORKOUT, CALL, STOPWATCH, CUSTOM
}

sealed class NowBarCard(
    open val type: CardType,
    open val title: String,
    open val icon: IconCompat,
    open val accentColor: Int? = null,
    open val tapAction: PendingIntent? = null,
    open val chipText: String? = null
) {
    abstract fun toPrimaryInfo(): String
    abstract fun toSecondaryInfo(): String

    open fun toNowBarSecondaryInfo(): String? = null

    open fun toProgress(): Int? = null

    open fun toProgressMax(): Int = 100

    open fun toChipText(): String? =
        chipText ?: toNowBarSecondaryInfo() ?: toSecondaryInfo().takeIf { it.isNotBlank() }

    open fun toChipIcon(): IconCompat = icon

    open fun toChipBackgroundColor(): Int? = accentColor

    open fun toNowBarIcon(): IconCompat? = null

    open fun toSecondIcon(): IconCompat? = null

    open fun toNowBarPrimaryInfo(): String? = null

    /** Substitution name shown in the notification (e.g. "Stopwatch", "Timer"). */
    open fun toSubstName(): String? = title

    /** PendingIntent fired when the Now Bar sub-screen is tapped. */
    open fun toNowBarSubScreenIntent(): PendingIntent? = null

    /** Whether this card supports a live chronometer in the Now Bar. */
    open fun hasChronometerSupport(): Boolean = false

    /** Action primary set value for collapsed Now Bar buttons (typically 1). */
    open fun toActionPrimarySet(): Int = 1

    /** First/main icon for the Now Bar view, separate from chip icon. */
    open fun toFirstIcon(): IconCompat? = null

    /** Icon displayed next to secondary info text in the Now Bar. */
    open fun toSecondaryInfoIcon(): IconCompat? = null

    /** Action button background color for the Now Bar. */
    open fun toActionBgColor(): Int? = accentColor
}
