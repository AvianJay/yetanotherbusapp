package tw.avianjay.taiwanbus.flutter

object NativeApiUserAgent {
    fun value(platform: String = "android"): String {
        val version = sanitize(BuildConfig.VERSION_NAME)
        val gitSha = sanitize(BuildConfig.GIT_SHA)
        return "YABus/$version-$gitSha ($platform)"
    }

    private fun sanitize(value: String?): String {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return "unknown"
        }
        return trimmed.replace(Regex("\\s+"), "_")
    }
}