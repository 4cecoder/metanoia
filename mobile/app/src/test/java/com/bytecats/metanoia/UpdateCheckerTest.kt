package com.bytecats.metanoia

import com.bytecats.metanoia.update.NightlyUpdateInfo
import com.bytecats.metanoia.update.UpdateChecker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-logic coverage for UpdateChecker.parseRelease / extractCommitSha /
 * isUpdateAvailable — none of these touch Android or the network, so they
 * run on the plain JVM (this module's testImplementation adds the real
 * org.json jar so JSONObject/JSONArray don't hit the "Stub!" Android SDK jar).
 */
class UpdateCheckerTest {

    private val fullShaOne = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

    private val realisticReleaseJson = """
        {
          "url": "https://api.github.com/repos/4cecoder/metanoia/releases/12345",
          "html_url": "https://github.com/4cecoder/metanoia/releases/tag/latest",
          "id": 12345,
          "tag_name": "latest",
          "target_commitish": "master",
          "name": "Latest (master @ $fullShaOne)",
          "draft": false,
          "prerelease": true,
          "created_at": "2026-07-22T01:02:03Z",
          "published_at": "2026-07-22T01:05:00Z",
          "body": "Automatically rebuilt from the latest commit on `master`\n($fullShaOne). This asset is replaced on every push.\n\ncommit: $fullShaOne\n\nAndroid build is DEBUG-SIGNED (sideload only, not from the Play\nStore) — see docs/PACKAGING.md for what a real signed release\nneeds.",
          "assets": [
            {
              "name": "metanoia-android-debug.apk",
              "browser_download_url": "https://github.com/4cecoder/metanoia/releases/download/latest/metanoia-android-debug.apk",
              "size": 123456789,
              "content_type": "application/vnd.android.package-archive"
            },
            {
              "name": "some-other-artifact.txt",
              "browser_download_url": "https://github.com/4cecoder/metanoia/releases/download/latest/some-other-artifact.txt",
              "size": 42,
              "content_type": "text/plain"
            }
          ]
        }
    """.trimIndent()

    // -------------------------------------------------------------------
    // parseRelease — happy path
    // -------------------------------------------------------------------

    @Test
    fun parseReleaseExtractsAllFieldsFromRealisticResponse() {
        val info = UpdateChecker.parseRelease(realisticReleaseJson)
        assertNotNull("Expected a parsed NightlyUpdateInfo", info)
        info!!
        assertEquals("latest", info.tagName)
        assertEquals(fullShaOne, info.commitSha)
        assertEquals("2026-07-22T01:05:00Z", info.publishedAt)
        assertEquals("https://github.com/4cecoder/metanoia/releases/tag/latest", info.htmlUrl)
        assertEquals(
            "https://github.com/4cecoder/metanoia/releases/download/latest/metanoia-android-debug.apk",
            info.downloadUrl
        )
    }

    // -------------------------------------------------------------------
    // parseRelease — malformed / degenerate input
    // -------------------------------------------------------------------

    @Test
    fun parseReleaseReturnsNullForEmptyJsonObject() {
        assertNull(UpdateChecker.parseRelease("{}"))
    }

    @Test
    fun parseReleaseReturnsNullForNotJson() {
        assertNull(UpdateChecker.parseRelease("not json"))
    }

    @Test
    fun parseReleaseReturnsNullForBlankInput() {
        assertNull(UpdateChecker.parseRelease(""))
    }

    @Test
    fun parseReleaseReturnsNullWhenTagNameMissing() {
        val json = """{"body": "commit: $fullShaOne"}"""
        assertNull(UpdateChecker.parseRelease(json))
    }

    @Test
    fun parseReleaseReturnsNullWhenTagNameBlank() {
        val json = """{"tag_name": "   ", "body": "commit: $fullShaOne"}"""
        assertNull(UpdateChecker.parseRelease(json))
    }

    @Test
    fun parseReleaseHandlesMissingAssetsArray() {
        val json = """{"tag_name": "latest", "body": "commit: $fullShaOne"}"""
        val info = UpdateChecker.parseRelease(json)
        assertNotNull(info)
        assertNull(info!!.downloadUrl)
        assertEquals(fullShaOne, info.commitSha)
    }

    @Test
    fun parseReleaseHandlesAssetsArrayWithoutMatchingApk() {
        val json = """
            {"tag_name": "latest", "assets": [{"name": "irrelevant.txt", "browser_download_url": "https://example.com/x"}]}
        """.trimIndent()
        val info = UpdateChecker.parseRelease(json)
        assertNotNull(info)
        assertNull(info!!.downloadUrl)
    }

    // -------------------------------------------------------------------
    // extractCommitSha (exercised through parseRelease's body field)
    // -------------------------------------------------------------------

    @Test
    fun parseReleaseCommitShaIsNullWhenBodyHasNoCommitLine() {
        val json = """{"tag_name": "latest", "body": "no sha info here"}"""
        val info = UpdateChecker.parseRelease(json)
        assertNotNull(info)
        assertNull(info!!.commitSha)
    }

    @Test
    fun extractCommitShaIsCaseInsensitiveAndTrimsWhitespace() {
        val sha = UpdateChecker.extractCommitSha("  Commit:   $fullShaOne  \nmore text")
        assertEquals(fullShaOne, sha)
    }

    @Test
    fun extractCommitShaAcceptsShortSha() {
        val sha = UpdateChecker.extractCommitSha("commit: a1b2c3d")
        assertEquals("a1b2c3d", sha)
    }

    @Test
    fun extractCommitShaNullWhenNoMatch() {
        assertNull(UpdateChecker.extractCommitSha("nothing relevant"))
    }

    // -------------------------------------------------------------------
    // isUpdateAvailable
    // -------------------------------------------------------------------

    @Test
    fun isUpdateAvailableFalseWhenFetchedIsNull() {
        assertFalse(UpdateChecker.isUpdateAvailable(fullShaOne, null))
    }

    @Test
    fun isUpdateAvailableFalseWhenFetchedCommitShaIsNull() {
        val info = NightlyUpdateInfo("latest", null, null, null, null)
        assertFalse(UpdateChecker.isUpdateAvailable(fullShaOne, info))
    }

    @Test
    fun isUpdateAvailableFalseWhenShasAreIdentical() {
        val info = NightlyUpdateInfo("latest", fullShaOne, null, null, null)
        assertFalse(UpdateChecker.isUpdateAvailable(fullShaOne, info))
    }

    @Test
    fun isUpdateAvailableTrueWhenShasDiffer() {
        val otherSha = "9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f"
        val info = NightlyUpdateInfo("latest", otherSha, null, null, null)
        assertTrue(UpdateChecker.isUpdateAvailable(fullShaOne, info))
    }

    @Test
    fun isUpdateAvailableFalseWhenRemoteShortShaIsPrefixOfCurrentFullSha() {
        val shortSha = fullShaOne.take(7)
        val info = NightlyUpdateInfo("latest", shortSha, null, null, null)
        assertFalse(UpdateChecker.isUpdateAvailable(fullShaOne, info))
    }

    @Test
    fun isUpdateAvailableFalseWhenCurrentShortShaIsPrefixOfRemoteFullSha() {
        val shortSha = fullShaOne.take(7)
        val info = NightlyUpdateInfo("latest", fullShaOne, null, null, null)
        assertFalse(UpdateChecker.isUpdateAvailable(shortSha, info))
    }

    @Test
    fun isUpdateAvailableTrueWhenCurrentShaIsBlank() {
        val info = NightlyUpdateInfo("latest", fullShaOne, null, null, null)
        assertTrue(UpdateChecker.isUpdateAvailable("", info))
    }
}
