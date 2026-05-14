package com.nowbar.api.notification

import android.app.PendingIntent
import android.widget.RemoteViews
import androidx.annotation.ColorInt

/**
 * Configuration for the Samsung foldable cover screen capsule widget.
 *
 * Samsung devices with cover screens (Flip/Fold) display a capsule widget
 * for ongoing activities. The capsule shows a custom [RemoteViews] layout
 * with gradient background and optional tap action.
 *
 * Discovered in Samsung Voice Recorder's `NotiRemoteViewManager`:
 * - `isCapsule` = true to enable capsule mode
 * - `capsule_layout` = custom RemoteViews
 * - `capsule_action` = PendingIntent for tap
 * - `bg_startColor` / `bg_endColor` = gradient colors
 * - `capsule_priority` = "normal" or "low"
 *
 * @param layout        Custom [RemoteViews] layout for the capsule.
 * @param action        [PendingIntent] fired when the capsule is tapped, or null.
 * @param bgStartColor  Gradient start color for the capsule background.
 * @param bgEndColor    Gradient end color for the capsule background.
 * @param priority      Display priority: "normal" or "low". Low priority capsules may be hidden.
 */
data class CapsuleConfig(
    val layout: RemoteViews,
    val action: PendingIntent? = null,
    @ColorInt val bgStartColor: Int,
    @ColorInt val bgEndColor: Int,
    val priority: String? = null
)
