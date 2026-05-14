package com.nowbar.api.notification

import android.graphics.drawable.Icon

data class ProgressSegment(
    val startPosition: Float,
    val color: Int,
    val icon: Icon? = null
)