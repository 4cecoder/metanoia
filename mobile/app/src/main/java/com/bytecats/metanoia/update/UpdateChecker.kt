package com.bytecats.metanoia.update

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

/**
 * Result of parsing the GitHub Releases API response for the rolling
 * "latest" nightly/master build tag (see .github/workflows/release-android.yml).
 */
data class NightlyUpdateInfo(
    val tagName: String,
    val commitSha: String?,
    val publishedAt: String?,
    val htmlUrl: String?,
    val downloadUrl: String?
)

/**
 * Opt-in nightly/experimental update checker.
 *
 * `parseRelease` and `isUpdateAvailable` are pure functions with no Android
 * dependency so they can be unit tested on the plain JVM without Robolectric.
 * `fetchLatest` is the only part that touches the network.
 */
object UpdateChecker {

    const val RELEASES_API_URL = "https://api.github.com/repos/4cecoder/metanoia/releases/tags/latest"
    const val APK_ASSET_NAME = "metanoia-android-debug.apk"

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
     * Parses a GitHub Releases API JSON response body. Returns null on any
     * malformed input (missing/blank tag_name, invalid JSON, unexpected
     * types) rather than throwing.
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
                    if (asset.optString("name") == APK_ASSET_NAME) {
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
     * Blocking GET to the GitHub Releases API for the "latest" rolling tag,
     * wrapped onto Dispatchers.IO. Returns null on any network exception or
     * non-2xx response — never throws.
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
