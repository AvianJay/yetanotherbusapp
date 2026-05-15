package com.nowbar.api.notification

import android.widget.RemoteViews

/**
 * Configuration for a live chronometer displayed in the Samsung Now Bar.
 *
 * Samsung apps (Voice Recorder, Clock) embed a [RemoteViews] containing an
 * `android.widget.Chronometer` into the ongoing notification extras. The system
 * renders this chronometer in the Now Bar chip or expanded view.
 *
 * @param remoteView    [RemoteViews] containing the Chronometer widget.
 * @param tag           Identifier tag for the chronometer (used by the system to track the view).
 * @param viewPosition  Position in the notification layout: 1 = primary info, 2 = secondary info.
 * @param nowBarPosition Position in the collapsed Now Bar chip: 1 = primary, 2 = secondary.
 */
data class ChronometerConfig(
    val remoteView: RemoteViews,
    val tag: String? = null,
    val viewPosition: Int = ChronometerPosition.SECONDARY_INFO,
    val nowBarPosition: Int = ChronometerPosition.SECONDARY_INFO
)

/** Position constants for chronometer placement. */
object ChronometerPosition {
    /** Replace primary info with the chronometer. */
    const val PRIMARY_INFO = 1
    /** Replace secondary info with the chronometer. */
    const val SECONDARY_INFO = 2
}
