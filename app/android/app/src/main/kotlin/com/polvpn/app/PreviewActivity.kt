package com.polvpn.app

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class PreviewActivity : FlutterActivity() {
    private data class Export(val text: String, val reply: MethodChannel.Result)
    private enum class ExportOutcome { SAVED, CANCELED, FAILED }

    private var previewChannel: MethodChannel? = null
    private var pendingExport: Export? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pol/preview")
        previewChannel = channel
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "deviceInfo" -> reply.success(
                    mapOf(
                        "androidVersion" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                        "architecture" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "Unknown"),
                    ),
                )
                "exportDiagnostics" -> {
                    val text = (call.arguments as? Map<*, *>)?.get("text") as? String
                    requestExport(text, reply)
                }
                else -> reply.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        previewChannel?.setMethodCallHandler(null)
        previewChannel = null
        pendingExport?.let { completeExport(it, ExportOutcome.FAILED) }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Suppress("DEPRECATION")
    private fun requestExport(text: String?, reply: MethodChannel.Result) {
        if (text.isNullOrBlank()) {
            reply.error("invalid_report", "The diagnostic report is empty.", null)
            return
        }
        if (pendingExport != null) {
            reply.error("export_in_progress", "A diagnostic report export is already in progress.", null)
            return
        }

        val export = Export(text, reply)
        pendingExport = export
        val picker = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TITLE, "pol-vpn-diagnostics.txt")
            .putExtra(Intent.EXTRA_LOCAL_ONLY, true)
        try {
            startActivityForResult(picker, EXPORT_REQUEST)
        } catch (_: RuntimeException) {
            completeExport(export, ExportOutcome.FAILED)
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != EXPORT_REQUEST) return
        val export = pendingExport ?: return
        if (resultCode != RESULT_OK) {
            completeExport(export, ExportOutcome.CANCELED)
            return
        }
        val destination = data?.data
        if (destination?.scheme != ContentResolver.SCHEME_CONTENT) {
            completeExport(export, ExportOutcome.FAILED)
            return
        }

        Thread {
            val outcome = writeReport(destination, export.text)
            runOnUiThread { completeExport(export, outcome) }
        }.start()
    }

    private fun writeReport(destination: Uri, text: String): ExportOutcome {
        return try {
            val stream = contentResolver.openOutputStream(destination, "wt") ?: return ExportOutcome.FAILED
            stream.bufferedWriter(Charsets.UTF_8).use { it.write(text) }
            ExportOutcome.SAVED
        } catch (_: IOException) {
            ExportOutcome.FAILED
        } catch (_: RuntimeException) {
            ExportOutcome.FAILED
        }
    }

    private fun completeExport(export: Export, outcome: ExportOutcome) {
        if (pendingExport !== export) return
        pendingExport = null
        when (outcome) {
            ExportOutcome.SAVED -> export.reply.success(true)
            ExportOutcome.CANCELED -> export.reply.success(false)
            ExportOutcome.FAILED -> export.reply.error(
                "export_failed", "Android could not save the diagnostic report.", null,
            )
        }
    }

    private companion object {
        const val EXPORT_REQUEST = 0x504f
    }
}
