package com.nowbar.api

/**
 * Represents the platform providing Now Bar / ambient display functionality.
 */
enum class NowBarPlatform {
    /** Samsung One UI 7+ Now Bar via ongoing activity extras. */
    SAMSUNG,

    /** Google Ambient Data API (Pixel devices). */
    GOOGLE,

    /** OPPO/OnePlus Ambient Alerts feature. */
    OPPO,

    /** Android 16+ native Live Updates API. */
    ANDROID_16,

    /** No supported Now Bar platform detected. */
    NONE
}