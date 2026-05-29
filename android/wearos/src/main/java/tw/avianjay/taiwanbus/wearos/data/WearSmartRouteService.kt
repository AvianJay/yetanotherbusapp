package tw.avianjay.taiwanbus.wearos.data

import java.util.Calendar
import kotlin.math.max

/**
 * Lightweight port of the phone-side `SmartRouteService` scoring algorithm so
 * the watch can recommend a route even when the phone is offline.
 *
 * Only the time-of-day heuristics are kept; we deliberately drop the location
 * + route-detail lookup pieces because the Tile / Complication paths must be
 * cheap and synchronous.
 */
object WearSmartRouteService {
    private const val minTotalOpens = 3
    private const val minRelevantInteractions = 2
    private const val recencyWindowDays = 7L

    fun chooseSuggestion(
        profiles: List<WearRouteUsageProfile>,
        preferredProvider: String,
        now: Long,
    ): WearSmartSuggestionPayload? {
        if (profiles.isEmpty()) {
            return null
        }
        val scoped = profiles.filter {
            it.provider.equals(preferredProvider, ignoreCase = true)
        }.ifEmpty { profiles }

        val nowHour = hourOf(now)
        val prevHour = (nowHour + 23) % 24
        val nextHour = (nowHour + 1) % 24

        var bestProfile: WearRouteUsageProfile? = null
        var bestScore = 0.0

        for (profile in scoped) {
            if (!hasEnoughHistory(profile, nowHour, prevHour, nextHour, now)) {
                continue
            }
            val score = scoreProfile(profile, nowHour, prevHour, nextHour, now)
            if (score > bestScore) {
                bestProfile = profile
                bestScore = score
            }
        }

        val profile = bestProfile ?: return null
        return WearSmartSuggestionPayload(
            routeId = profile.routeId,
            routeName = profile.routeName.ifBlank { profile.routeKey.toString() },
            provider = profile.provider,
            reason = "根據你的使用習慣。",
            source = "local",
            generatedAtMs = now,
        )
    }

    private fun hasEnoughHistory(
        profile: WearRouteUsageProfile,
        nowHour: Int,
        prevHour: Int,
        nextHour: Int,
        now: Long,
    ): Boolean {
        if (profile.totalOpens < minTotalOpens) {
            return false
        }
        val relevant = combinedCountAtHour(profile, nowHour, now) +
                combinedCountAtHour(profile, prevHour, now) +
                combinedCountAtHour(profile, nextHour, now)
        return relevant >= minRelevantInteractions
    }

    private fun scoreProfile(
        profile: WearRouteUsageProfile,
        nowHour: Int,
        prevHour: Int,
        nextHour: Int,
        now: Long,
    ): Double {
        val currentOpens = profile.hourlyOpens[nowHour] ?: 0
        val currentSelections = selectionCountAtHour(profile, nowHour, now)
        val adjacentOpens = (profile.hourlyOpens[prevHour] ?: 0) + (profile.hourlyOpens[nextHour] ?: 0)
        val adjacentSelections = selectionCountAtHour(profile, prevHour, now) +
                selectionCountAtHour(profile, nextHour, now)
        val recencyDays = if (profile.lastOpenedAtMs <= 0L) {
            365L
        } else {
            max(0L, (now - profile.lastOpenedAtMs) / (24L * 60L * 60L * 1000L))
        }
        val recencyBonus = when {
            recencyDays <= 2L -> 1.5
            recencyDays <= 7L -> 0.75
            else -> 0.0
        }
        return (currentOpens * 5.0) +
                (currentSelections * 3.5) +
                (adjacentOpens * 2.5) +
                (adjacentSelections * 1.5) +
                (profile.totalOpens * 0.15) +
                recencyBonus
    }

    private fun combinedCountAtHour(
        profile: WearRouteUsageProfile,
        hour: Int,
        now: Long,
    ): Int = (profile.hourlyOpens[hour] ?: 0) + selectionCountAtHour(profile, hour, now)

    private fun selectionCountAtHour(
        profile: WearRouteUsageProfile,
        hour: Int,
        now: Long,
    ): Int {
        if (profile.recentSelectionMs.isEmpty()) {
            return 0
        }
        val cutoff = now - recencyWindowDays * 24L * 60L * 60L * 1000L
        var count = 0
        for (timestamp in profile.recentSelectionMs) {
            if (timestamp < cutoff) continue
            if (hourOf(timestamp) == hour) count += 1
        }
        return count
    }

    private fun hourOf(epochMs: Long): Int {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = epochMs
        return calendar.get(Calendar.HOUR_OF_DAY)
    }
}
