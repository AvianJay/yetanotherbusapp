package com.nowbar.api.notification

import android.graphics.drawable.Icon

/**
 * Configuration for the Now Bar chip appearance.
 *
 * @param icon           Chip icon displayed in the collapsed Now Bar pill.
 * @param backgroundColor Chip background color.
 * @param expandedText   Text shown when the chip is expanded.
 * @param firstIcon      First/main icon in the Now Bar view, separate from chip icon.
 *                       Used by Samsung Voice Recorder as `android.ongoingActivityNoti.firstIcon`.
 */
data class ChipConfig(
    val icon: Icon? = null,
    val backgroundColor: Int? = null,
    val expandedText: String? = null,
    val firstIcon: Icon? = null
)