package com.biso.no

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var expenseIntakeChannel: MethodChannel? = null
    private val pendingExpenseBatches = mutableListOf<Map<String, Any>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        expenseIntakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "biso/expense_intake"
        )
        collectExpenseShareIntent(intent)?.let { pendingExpenseBatches.add(it) }
        expenseIntakeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingExpenseIntakeBatches" -> {
                    val batches = pendingExpenseBatches.toList()
                    pendingExpenseBatches.clear()
                    result.success(batches)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectExpenseShareIntent(intent)?.let {
            pendingExpenseBatches.add(it)
            expenseIntakeChannel?.invokeMethod("expenseIntakeReceived", null)
        }
    }

    private fun collectExpenseShareIntent(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val uris = when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri == null) emptyList() else listOf(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            }
            else -> emptyList()
        }
        if (uris.isEmpty()) return null

        val batchId = "android_${System.currentTimeMillis()}_${UUID.randomUUID()}"
        val batchDir = File(filesDir, "expense_intake_native/$batchId")
        batchDir.mkdirs()
        val files = uris.mapNotNull { copySharedUri(it, batchDir) }
        // Say so whenever a file is left behind. Dropping it here, in a
        // share that was otherwise fine, is a receipt that vanishes without
        // a word.
        if (files.isEmpty()) {
            batchDir.delete()
            Toast.makeText(this, UNSUPPORTED_SHARE_MESSAGE, Toast.LENGTH_LONG).show()
            return null
        }
        val refused = uris.size - files.size
        if (refused > 0) {
            Toast.makeText(this, partlyRefusedMessage(refused), Toast.LENGTH_LONG).show()
        }
        return mapOf(
            "batchId" to batchId,
            "source" to "android-share",
            "files" to files
        )
    }

    private fun copySharedUri(uri: Uri, batchDir: File): Map<String, Any>? {
        val mimeType = contentResolver.getType(uri) ?: mimeTypeFromName(displayName(uri))
        if (!isSupportedMimeType(mimeType)) return null
        val originalName = displayName(uri)
        val fileName = uniqueFileName(batchDir, sanitizeFileName(originalName, mimeType))
        val destination = File(batchDir, fileName)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            mapOf(
                "fileName" to fileName,
                "filePath" to destination.absolutePath,
                "mimeType" to mimeType,
                "sizeBytes" to destination.length()
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val nameIndex = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && cursor.moveToFirst() && nameIndex >= 0) {
                cursor.getString(nameIndex)
            } else {
                uri.lastPathSegment ?: "receipt"
            }
        } catch (_: Exception) {
            uri.lastPathSegment ?: "receipt"
        } finally {
            cursor?.close()
        }
    }

    // The reimbursement API accepts these and nothing else, so neither may
    // this: a HEIC or WebP photo copied in here was dropped by the app
    // afterwards, silently.
    private fun isSupportedMimeType(mimeType: String): Boolean {
        return setOf(
            "application/pdf",
            "image/jpeg",
            "image/jpg",
            "image/png"
        ).contains(mimeType.lowercase())
    }

    private fun mimeTypeFromName(name: String): String {
        return when (name.substringAfterLast('.', "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "pdf" -> "application/pdf"
            "png" -> "image/png"
            else -> "application/octet-stream"
        }
    }

    private fun sanitizeFileName(name: String, mimeType: String): String {
        val cleaned = name.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "receipt" }
        val base = cleaned.substringBeforeLast('.', cleaned).ifBlank { "receipt" }
        // The app decides what it will accept by file extension, so a name
        // that disagrees with the type the provider actually handed over
        // would have it refuse a file it can read perfectly well.
        return if (mimeTypeFromName(cleaned) == mimeType.lowercase()) {
            cleaned
        } else {
            "$base.${extensionForMimeType(mimeType)}"
        }
    }

    private fun extensionForMimeType(mimeType: String): String {
        return when (mimeType.lowercase()) {
            "application/pdf" -> "pdf"
            "image/png" -> "png"
            else -> "jpg"
        }
    }

    private fun uniqueFileName(directory: File, requested: String): String {
        val dot = requested.lastIndexOf('.')
        val base = if (dot > 0) requested.substring(0, dot) else requested
        val extension = if (dot > 0) requested.substring(dot) else ""
        var candidate = requested
        var index = 1
        while (File(directory, candidate).exists()) {
            candidate = "${base}_$index$extension"
            index += 1
        }
        return candidate
    }

    companion object {
        private const val UNSUPPORTED_SHARE_MESSAGE =
            "BISO Expenses takes PDF, PNG and JPEG receipts. Add a photo in " +
                "another format from inside the BISO app \u2014 it converts it for you."

        // Android 12+ shows two lines of a text toast at most, so the count
        // and the rule come first and nothing else is said.
        private fun partlyRefusedMessage(refused: Int): String {
            val files = if (refused == 1) "1 file was" else "$refused files were"
            return "$files not added. BISO takes PDF, PNG and JPEG."
        }
    }
}
