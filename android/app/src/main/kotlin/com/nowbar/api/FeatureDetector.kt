package com.nowbar.api

import android.content.Context
import android.os.Build

/**
 * Runtime feature detection.
 *
 * Public API stays simple:
 * - Samsung extras path
 * - Android 16 Live Updates path
 * - basic notification fallback
 *
 * Google / OPPO feature flags are still exposed because they were already present
 * in the original source, but the actual render backends remain Samsung extras
 * and standard Android Live Updates.
 */
object FeatureDetector {

    const val FEATURE_SAMSUNG_NOWBAR = "com.samsung.feature.nowbar"
    const val FEATURE_GOOGLE_AMBIENT = "com.google.android.feature.AMBIENT_DATA"
    const val FEATURE_OPPO_AMBIENT = "com.oplus.software.feature.ambient_alerts"

    private const val ANDROID_16_SDK = 36

    @JvmStatic
    fun isSamsungNowBarSupported(context: Context): Boolean {
        // Check explicit feature flag first
        if (context.packageManager.hasSystemFeature(FEATURE_SAMSUNG_NOWBAR)) {
            return true
        }

        // Fallback: Samsung devices with One UI 7+ support Now Bar via ongoing activity extras
        // even if the feature flag isn't properly advertised
        if (Build.MANUFACTURER.equals("Samsung", ignoreCase = true) ||
            Build.BRAND.equals("Samsung", ignoreCase = true)) {
            // One UI 7 is based on Android 15 (API 35)
            // But some devices might get it on Android 14 (API 34) via updates
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        }

        return false
    }

    @JvmStatic
    fun isGoogleAmbientSupported(context: Context): Boolean =
        context.packageManager.hasSystemFeature(FEATURE_GOOGLE_AMBIENT)

    @JvmStatic
    fun isOppoAmbientSupported(context: Context): Boolean =
        context.packageManager.hasSystemFeature(FEATURE_OPPO_AMBIENT)

    @JvmStatic
    fun isAndroid16LiveUpdatesSupported(): Boolean =
        Build.VERSION.SDK_INT >= ANDROID_16_SDK

    /**
     * "Supported" here means the module can try a native enhanced surface now:
     * Samsung Now Bar extras or Android 16 promoted ongoing / Live Updates.
     */
    @JvmStatic
    fun isNativeSurfaceSupported(context: Context): Boolean =
        isSamsungNowBarSupported(context) || isAndroid16LiveUpdatesSupported()

    @JvmStatic
    fun isAnyNowBarSupported(context: Context): Boolean = isNativeSurfaceSupported(context)

    @JvmStatic
    fun getSupportedPlatform(context: Context): NowBarPlatform {
        return when {
            isSamsungNowBarSupported(context) -> NowBarPlatform.SAMSUNG
            isAndroid16LiveUpdatesSupported() -> NowBarPlatform.ANDROID_16
            isGoogleAmbientSupported(context) -> NowBarPlatform.GOOGLE
            isOppoAmbientSupported(context) -> NowBarPlatform.OPPO
            else -> NowBarPlatform.NONE
        }
    }
}
