package com.nowbar.api.cards

import android.app.PendingIntent
import androidx.core.graphics.drawable.IconCompat

data class CustomCard(
    override val title: String,
    override val icon: IconCompat,
    override val accentColor: Int? = null,
    override val tapAction: PendingIntent? = null,
    override val chipText: String? = null,
    val primaryText: String,
    val secondaryText: String? = null,
    val nowBarText: String? = null,
    val progressValue: Int? = null,
    val progressMax: Int = 100,
    val customProgressColor: Int? = null,
    val firstIcon: IconCompat? = null,
    val secondaryInfoIcon: IconCompat? = null,
    val subScreenIntent: PendingIntent? = null
) : NowBarCard(
    type = CardType.CUSTOM,
    title = title,
    icon = icon,
    accentColor = accentColor,
    tapAction = tapAction,
    chipText = chipText
) {
    override fun toPrimaryInfo(): String = primaryText

    override fun toSecondaryInfo(): String = secondaryText ?: ""

    override fun toNowBarSecondaryInfo(): String? = nowBarText

    override fun toProgress(): Int? = progressValue?.coerceIn(0, progressMax)

    override fun toProgressMax(): Int = progressMax

    override fun toNowBarPrimaryInfo(): String = primaryText

    override fun toSubstName(): String = title

    override fun toFirstIcon(): IconCompat? = firstIcon

    override fun toSecondaryInfoIcon(): IconCompat? = secondaryInfoIcon

    override fun toNowBarSubScreenIntent(): PendingIntent? = subScreenIntent

    class Builder(
        private val title: String,
        private val icon: IconCompat,
        private val primaryText: String
    ) {
        private var accentColor: Int? = null
        private var tapAction: PendingIntent? = null
        private var chipText: String? = null
        private var secondaryText: String? = null
        private var nowBarText: String? = null
        private var progressValue: Int? = null
        private var progressMax: Int = 100
        private var customProgressColor: Int? = null
        private var firstIcon: IconCompat? = null
        private var secondaryInfoIcon: IconCompat? = null
        private var subScreenIntent: PendingIntent? = null

        fun accentColor(color: Int) = apply { this.accentColor = color }
        fun tapAction(action: PendingIntent) = apply { this.tapAction = action }
        fun chipText(text: String) = apply { this.chipText = text }
        fun secondaryText(text: String) = apply { this.secondaryText = text }
        fun nowBarText(text: String) = apply { this.nowBarText = text }
        fun progressValue(value: Int) = apply { this.progressValue = value }
        fun progressMax(max: Int) = apply { this.progressMax = max }
        fun customProgressColor(color: Int) = apply { this.customProgressColor = color }
        fun firstIcon(icon: IconCompat) = apply { this.firstIcon = icon }
        fun secondaryInfoIcon(icon: IconCompat) = apply { this.secondaryInfoIcon = icon }
        fun subScreenIntent(intent: PendingIntent) = apply { this.subScreenIntent = intent }

        fun build(): CustomCard = CustomCard(
            title = title,
            icon = icon,
            accentColor = accentColor,
            tapAction = tapAction,
            chipText = chipText,
            primaryText = primaryText,
            secondaryText = secondaryText,
            nowBarText = nowBarText,
            progressValue = progressValue,
            progressMax = progressMax,
            customProgressColor = customProgressColor,
            firstIcon = firstIcon,
            secondaryInfoIcon = secondaryInfoIcon,
            subScreenIntent = subScreenIntent
        )

        companion object {
            @JvmStatic
            fun create(title: String, icon: IconCompat, primaryText: String) =
                Builder(title, icon, primaryText)
        }
    }
}