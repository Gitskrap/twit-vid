package com.alchemistaloha.xflow

import android.os.SystemClock
import android.os.Build
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import java.io.File
import androidx.core.content.FileProvider
import org.json.JSONObject
import android.view.KeyEvent
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Volume buttons control Cast while connected; otherwise Android behaves normally. */
class MainActivity : FlutterFragmentActivity() {
    private var previousSession: CastSession? = null
    private var requestedVolume = Double.NaN
    private var lastChangeAt = 0L

    private fun currentCast(): CastSession? = try {
        CastContext.getSharedInstance(this).sessionManager.currentCastSession
            ?.takeIf { it.isConnected }
    } catch (_: Exception) {
        null
    }

    private fun changeCastVolume(session: CastSession, direction: Int) {
        val now = SystemClock.elapsedRealtime()
        if (previousSession !== session || requestedVolume.isNaN() || now - lastChangeAt > 1500) {
            requestedVolume = session.volume
        }
        previousSession = session
        requestedVolume = (requestedVolume + direction * 0.05).coerceIn(0.0, 1.0)
        if (direction > 0 && session.isMute) session.setMute(false)
        session.setVolume(requestedVolume)
        lastChangeAt = now
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val direction = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 1
            KeyEvent.KEYCODE_VOLUME_DOWN -> -1
            else -> return super.dispatchKeyEvent(event)
        }
        val session = currentCast() ?: return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN) {
            try {
                changeCastVolume(session, direction)
            } catch (_: Exception) {
                return super.dispatchKeyEvent(event)
            }
        }
        // Consume both key-down and key-up only during a Cast session.
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // No APK, token or GitHub secret is embedded in this native channel.
        // Flutter downloads and verifies a GitHub Release before we show the
        // normal Android package installation confirmation.
        // Privacy diagnostics are a separate, opt-in export. Do not ever
        // read AppLogger, X credentials, subscription tables or media cache.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fr.twittervideo.client/diagnostics").setMethodCallHandler { call, result ->
            val dir = File(cacheDir, "anonymous-diagnostics")
            val reportFile = File(dir, "twit-vid-anonyme.json")
            when (call.method) {
                "shareReport" -> {
                    try {
                        val report = call.argument<String>("json") ?: ""
                        if (report.isEmpty() || report.length > 400_000 ||
                            JSONObject(report).optString("format") !=
                                "twit_vid_anonymous_diagnostics_v1") {
                            result.error("INVALID_REPORT", "Rapport anonyme invalide", null)
                            return@setMethodCallHandler
                        }
                        dir.mkdirs()
                        reportFile.writeText(report, Charsets.UTF_8)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.updateprovider", reportFile)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "application/json"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newRawUri("Rapport", uri)
                        }
                        startActivity(Intent.createChooser(send,
                            "Partager le diagnostic anonyme"))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SHARE_FAILED",
                            "Le partage du rapport n'a pas pu être lancé", null)
                    }
                }
                "deleteReport" -> {
                    reportFile.delete()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fr.twittervideo.client/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledVersion" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                            info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf(
                            "name" to (info.versionName ?: "0.0.0"),
                            "code" to code
                        ))
                    } catch (error: Exception) {
                        result.error("VERSION_FAILED", error.message, null)
                    }
                }
                "canInstallPackages" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls()
                )
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ))
                        } else {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("PERMISSION_SETTINGS_FAILED", error.message, null)
                    }
                }
                "installApk" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()) {
                            result.error("INSTALL_PERMISSION_REQUIRED",
                                "Autorise l'installation de cette source Android", null)
                            return@setMethodCallHandler
                        }
                        val supplied = call.argument<String>("path") ?: ""
                        val apk = File(supplied).canonicalFile
                        val allowed = File(cacheDir, "app-updates").canonicalFile
                        if (!apk.path.startsWith(allowed.path + File.separator) ||
                            !apk.name.endsWith("-arm64.apk") ||
                            !apk.isFile || apk.length() <= 0L) {
                            result.error("INVALID_APK",
                                "Fichier APK absent ou non autorisé", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.updateprovider", apk)
                        val install = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newRawUri("APK", uri)
                        }
                        startActivity(install)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("INSTALL_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fr.twittervideo.client/cast_volume").setMethodCallHandler { call, result ->
            val session = currentCast()
            when (call.method) {
                "getVolume" -> {
                    try { result.success(session?.volume) }
                    catch (_: Exception) { result.success(null) }
                }
                "setVolume" -> {
                    val requested = call.argument<Double>("volume")
                    if (session == null || requested == null || !requested.isFinite()) {
                        result.error("NOT_CONNECTED", "Aucun Chromecast connecté", null)
                    } else {
                        try {
                            val value = requested.coerceIn(0.0, 1.0)
                            session.setVolume(value)
                            if (value > 0.0 && session.isMute) session.setMute(false)
                            previousSession = session
                            requestedVolume = value
                            lastChangeAt = SystemClock.elapsedRealtime()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("VOLUME_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
