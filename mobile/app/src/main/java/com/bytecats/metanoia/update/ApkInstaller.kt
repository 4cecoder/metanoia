package com.bytecats.metanoia.update

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException

/**
 * Downloads an update APK in-app and hands it straight to the system
 * package installer, instead of the previous flow (opening the browser on
 * the raw GitHub release asset URL, which meant the user had to separately
 * find the downloaded file in their Downloads app and tap it themselves).
 * Android still shows its own "install this app?" confirmation regardless —
 * REQUEST_INSTALL_PACKAGES (declared in AndroidManifest.xml) makes this
 * possible at all, it doesn't and can't bypass that system prompt.
 */
object ApkInstaller {

    /**
     * Downloads [url] into this app's own cache dir (not shared/external
     * storage, so no extra storage permission is needed), overwriting any
     * previous download at that same path. Returns the downloaded file, or
     * null on any network/IO failure — never throws.
     */
    suspend fun download(context: Context, url: String, client: OkHttpClient = OkHttpClient()): File? =
        withContext(Dispatchers.IO) {
            try {
                val dir = File(context.cacheDir, "apk-updates").apply { mkdirs() }
                val out = File(dir, "metanoia-update.apk")
                val request = Request.Builder().url(url).build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    val body = response.body ?: return@withContext null
                    out.outputStream().use { sink -> body.byteStream().copyTo(sink) }
                }
                out
            } catch (e: IOException) {
                null
            }
        }

    /**
     * Launches the system package installer for [apkFile] via a
     * FileProvider content:// URI — a bare file:// URI can't be granted to
     * the installer package on API 24+, which is exactly what the
     * <provider> entry in AndroidManifest.xml (authority
     * "<applicationId>.fileprovider") exists to work around.
     */
    fun install(context: Context, apkFile: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apkFile)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
