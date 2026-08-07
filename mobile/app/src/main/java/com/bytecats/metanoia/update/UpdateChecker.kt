package com.bytecats.metanoia.update

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

/**
 * Release channel for update checking
 */
enum class ReleaseChannel(val displayName: String, val suffix: String) {
    STABLE("Stable", ""),
    BETA("Beta", "-beta"),
    ALPHA("Alpha", "-alpha"),
    NIGHTLY("Nightly", "-nightly");

    companion object {
        fun fromString(value: String?): ReleaseChannel {
            return values().find { it.name == value } ?: STABLE
        }
    }
}

/**
 * Release information from GitHub
 */
data class ReleaseInfo(
    val tagName: String,
    val version: String,
    val name: String,
    val body: String,
    val htmlUrl: String?,
    val downloadUrl: String?,
    val publishedAt: String?,
    val commitSha: String?,
    val isPrerelease: Boolean,
    val channel: ReleaseChannel
)

/**
 * Result of parsing the GitHub Releases API response for the rolling
 * "latest" nightly/master build tag (see .github/workflows/release-android.yml).
 * @deprecated Use ReleaseInfo instead which includes channel information
 */
data class NightlyUpdateInfo(
    val tagName: String,
    val commitSha: String?,
    val publishedAt: String?,
    val htmlUrl: String?,
    val downloadUrl: String?
)

/**
 * Update checker supporting multiple release channels (alpha, beta, stable, nightly)
 *
 * For alpha/beta/stable: Fetches all releases and filters by tag suffix
 * For nightly: Uses the "latest" rolling tag (original behavior)
 *
 * `parseRelease` and `isUpdateAvailable` are pure functions with no Android
 * dependency so they can be unit tested on the plain JVM without Robolectric.
 * `fetchLatest` is the only part that touches the network.
 */
object UpdateChecker {

    const val RELEASES_API_URL = "https://api.github.com/repos/4cecoder/metanoia/releases/tags/latest"
    const val ALL_RELEASES_API_URL = "https://api.github.com/repos/4cecoder/metanoia/releases"
    const val APK_ASSET_NAME = "Metanoia-android-debug.apk"

    private const val TAG = "UpdateChecker"

    // Matches a line like "commit: <7-40 hex chars>", case-insensitive,
    // tolerating surrounding whitespace.
    private val COMMIT_SHA_REGEX = Regex("""(?i)commit:\s*([0-9a-f]{7,40})\s*""")

    // Fallback for when the body doesn't have an explicit "commit:" label —
    // this happened for real: a release-workflow body-text rewrite dropped
    // the labeled line while still mentioning the sha in prose (e.g.
    // "Rebuilt from `<sha>`"), which silently made every update check think
    // no commit sha was ever available (isUpdateAvailable degrades to
    // "false" when commitSha is null) — the whole checker looked broken
    // with no error anywhere. A bare 40-hex-char sha is unambiguous enough
    // to match unlabeled (unlike a short sha, which is too easily confused
    // with an unrelated hex-looking token), so this is a safe last resort.
    private val BARE_FULL_SHA_REGEX = Regex("""(?i)\b([0-9a-f]{40})\b""")

    /**
     * Fetch the latest release for the specified channel
     */
    suspend fun fetchLatestForChannel(
        channel: ReleaseChannel,
        client: OkHttpClient = OkHttpClient()
    ): ReleaseInfo? = withContext(Dispatchers.IO) {
        if (channel == ReleaseChannel.NIGHTLY) {
            // Use original nightly behavior
            fetchLatest(client)?.let { nightlyInfo ->
                ReleaseInfo(
                    tagName = nightlyInfo.tagName,
                    version = extractVersion(nightlyInfo.tagName),
                    name = nightlyInfo.tagName,
                    body = "",
                    htmlUrl = nightlyInfo.htmlUrl,
                    downloadUrl = nightlyInfo.downloadUrl,
                    publishedAt = nightlyInfo.publishedAt,
                    commitSha = nightlyInfo.commitSha,
                    isPrerelease = true,
                    channel = ReleaseChannel.NIGHTLY
                )
            }
        } else {
            // Fetch all releases and filter by channel
            fetchAllReleases(client).let { releases ->
                findLatestReleaseForChannel(releases, channel)
            }
        }
    }

    /**
     * Fetch all releases from GitHub API
     */
    private suspend fun fetchAllReleases(client: OkHttpClient): List<ReleaseInfo> =
        withContext(Dispatchers.IO) {
            try {
                val req = Request.Builder()
                    .url(ALL_RELEASES_API_URL)
                    .header("Accept", "application/vnd.github+json")
                    .get()
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext emptyList()
                    val body = resp.body?.string() ?: return@withContext emptyList()
                    parseAllReleases(body)
                }
            } catch (e: Exception) {
                Log.w(TAG, "fetchAllReleases failed: ${e.message}")
                emptyList()
            }
        }

    /**
     * Parse all releases from GitHub API response
     */
    private fun parseAllReleases(json: String): List<ReleaseInfo> {
        return try {
            val array = org.json.JSONArray(json)
            val releases = mutableListOf<ReleaseInfo>()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                parseReleaseInfo(obj)?.let { releases.add(it) }
            }
            releases
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse releases array: ${e.message}")
            emptyList()
        }
    }

    /**
     * Parse a single release from GitHub API response
     */
    private fun parseReleaseInfo(obj: JSONObject): ReleaseInfo? {
        return try {
            val tagName = obj.optString("tag_name", "").trim()
            if (tagName.isBlank()) return null

            val channel = detectChannelFromTagName(tagName)
            val version = extractVersion(tagName)

            val body = obj.optString("body", "")
            val commitSha = extractCommitSha(body)
            val publishedAt = obj.optString("published_at", "").ifBlank { null }
            val htmlUrl = obj.optString("html_url", "").ifBlank { null }
            val isPrerelease = obj.optBoolean("prerelease", false)

            var downloadUrl: String? = null
            val assets = obj.optJSONArray("assets")
            if (assets != null) {
                for (i in 0 until assets.length()) {
                    val asset = assets.optJSONObject(i) ?: continue
                    val name = asset.optString("name", "")
                    if (name.lowercase().endsWith(".apk")) {
                        downloadUrl = asset.optString("browser_download_url", "").ifBlank { null }
                        break
                    }
                }
            }

            ReleaseInfo(
                tagName = tagName,
                version = version,
                name = obj.optString("name", tagName),
                body = body,
                htmlUrl = htmlUrl,
                downloadUrl = downloadUrl,
                publishedAt = publishedAt,
                commitSha = commitSha,
                isPrerelease = isPrerelease,
                channel = channel
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse release: ${e.message}")
            null
        }
    }

    /**
     * Detect the release channel from the tag name
     */
    private fun detectChannelFromTagName(tagName: String): ReleaseChannel {
        val lowerTag = tagName.lowercase()
        return when {
            lowerTag.contains("-alpha") -> ReleaseChannel.ALPHA
            lowerTag.contains("-beta") -> ReleaseChannel.BETA
            lowerTag.contains("-nightly") -> ReleaseChannel.NIGHTLY
            else -> ReleaseChannel.STABLE
        }
    }

    /**
     * Extract version number from tag name (remove channel suffix and 'v' prefix)
     */
    private fun extractVersion(tagName: String): String {
        var version = tagName.removePrefix("v")
        for (channel in ReleaseChannel.values()) {
            if (channel.suffix.isNotEmpty()) {
                version = version.removeSuffix(channel.suffix)
            }
        }
        return version.trim()
    }

    /**
     * Find the latest release for the specified channel
     *
     * Logic:
     * - STABLE: Only returns stable releases (no suffix)
     * - BETA: Only returns beta releases (with -beta suffix)
     * - ALPHA: Only returns alpha releases (with -alpha suffix)
     */
    private fun findLatestReleaseForChannel(
        releases: List<ReleaseInfo>,
        channel: ReleaseChannel
    ): ReleaseInfo? {
        val filteredReleases = when (channel) {
            ReleaseChannel.STABLE -> releases.filter { it.channel == ReleaseChannel.STABLE }
            ReleaseChannel.BETA -> releases.filter { it.channel == ReleaseChannel.BETA }
            ReleaseChannel.ALPHA -> releases.filter { it.channel == ReleaseChannel.ALPHA }
            ReleaseChannel.NIGHTLY -> emptyList() // Handled separately
        }

        // GitHub returns releases in reverse chronological order already
        return filteredReleases.firstOrNull()
    }

    /**
     * Parses a GitHub Releases API JSON response body for the "latest" tag.
     * Returns null on any malformed input.
     * @deprecated Use fetchLatestForChannel instead for channel-aware updates
     */
    fun parseRelease(json: String): NightlyUpdateInfo? {
        return try {
            val obj = JSONObject(json)
            val tagName = obj.optString("tag_name", "").trim()
            if (tagName.isBlank()) return null

            val body = obj.optString("body", "")
            val commitSha = extractCommitSha(body)

            val publishedAt = obj.optString("published_at", "").ifBlank { null }
            val htmlUrl = obj.optString("html_url", "").ifBlank { null }

            var downloadUrl: String? = null
            val assets = obj.optJSONArray("assets")
            if (assets != null) {
                for (i in 0 until assets.length()) {
                    val asset = assets.optJSONObject(i) ?: continue
                    val name = asset.optString("name", "")
                    if (name.lowercase().endsWith(".apk")) {
                        downloadUrl = asset.optString("browser_download_url", "").ifBlank { null }
                        break
                    }
                }
            }

            NightlyUpdateInfo(
                tagName = tagName,
                commitSha = commitSha,
                publishedAt = publishedAt,
                htmlUrl = htmlUrl,
                downloadUrl = downloadUrl
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Extracts a commit sha from the release body: prefers an explicit
     * "commit: <sha>" line, falls back to a bare 40-char hex sha anywhere in
     * the text (see BARE_FULL_SHA_REGEX for why), or null if neither is
     * present.
     */
    fun extractCommitSha(body: String): String? =
        COMMIT_SHA_REGEX.find(body)?.groupValues?.get(1)
            ?: BARE_FULL_SHA_REGEX.find(body)?.groupValues?.get(1)

    /**
     * Pure comparison: is `fetched` a genuinely different build than the one
     * currently running (`currentCommitSha`)?
     *
     * - false if `fetched` is null, or `fetched.commitSha` is null (can't compare).
     * - true if `currentCommitSha` is blank (unknown build — can't prove we're
     *   current, so surface it).
     * - otherwise true iff neither sha is a prefix of the other (handles
     *   short-sha vs full-sha comparisons).
     */
    fun isUpdateAvailable(currentCommitSha: String, fetched: NightlyUpdateInfo?): Boolean {
        val remoteSha = fetched?.commitSha ?: return false
        if (currentCommitSha.isBlank()) return true
        return !(remoteSha.startsWith(currentCommitSha) || currentCommitSha.startsWith(remoteSha))
    }

    /**
     * Check if an update is available for ReleaseInfo (channel-aware version)
     */
    fun isUpdateAvailable(currentCommitSha: String, fetched: ReleaseInfo?): Boolean {
        val remoteSha = fetched?.commitSha ?: return false
        if (currentCommitSha.isBlank()) return true
        return !(remoteSha.startsWith(currentCommitSha) || currentCommitSha.startsWith(remoteSha))
    }

    /**
     * Blocking GET to the GitHub Releases API for the "latest" rolling tag,
     * wrapped onto Dispatchers.IO. Returns null on any network exception or
     * non-2xx response — never throws.
     * @deprecated Use fetchLatestForChannel instead for channel-aware updates
     */
    suspend fun fetchLatest(client: OkHttpClient = OkHttpClient()): NightlyUpdateInfo? =
        withContext(Dispatchers.IO) {
            try {
                val req = Request.Builder()
                    .url(RELEASES_API_URL)
                    .header("Accept", "application/vnd.github+json")
                    .get()
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val body = resp.body?.string() ?: return@withContext null
                    parseRelease(body)
                }
            } catch (e: Exception) {
                Log.w(TAG, "fetchLatest failed: ${e.message}")
                null
            }
        }
}