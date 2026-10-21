package rs.antonijevic.invoice2ips

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Prijem slike, PDF dokumenta ili teksta podeljenog iz druge aplikacije (ACTION_SEND),
 * kao i nativno renderovanje PDF stranica u slike pomoću Android PdfRenderer-a.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private var sharedImage: ByteArray? = null
        private var sharedPayload: Map<String, Any?>? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rs.antonijevic.invoice2ips/shared"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedImage" -> {
                    result.success(sharedImage)
                    sharedImage = null
                }
                "getSharedPayload" -> {
                    result.success(sharedPayload)
                    sharedPayload = null
                    sharedImage = null
                }
                "renderPdfPages" -> {
                    val pdfBytes = call.argument<ByteArray>("bytes")
                    if (pdfBytes == null || pdfBytes.isEmpty()) {
                        result.success(emptyList<ByteArray>())
                        return@setMethodCallHandler
                    }
                    Thread {
                        val pages = renderPdfBytesToPngPages(pdfBytes)
                        runOnUiThread {
                            result.success(pages)
                        }
                    }.start()
                }
                "getAppSignatureSha1" -> {
                    result.success(getAppSignatureSha1())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Renderuje stranice PDF dokumenta u PNG slike visoke rezolucije (~2000px po dužoj strani)
     * sa belom pozadinom, pogodne za QR skener, lokalni OCR i prikaz u aplikaciji.
     */
    private fun renderPdfBytesToPngPages(pdfBytes: ByteArray): List<ByteArray> {
        var tempFile: File? = null
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        val outputPages = mutableListOf<ByteArray>()

        try {
            tempFile = File.createTempFile("invoice_pdf_", ".pdf", cacheDir)
            tempFile.writeBytes(pdfBytes)
            pfd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)

            val count = renderer.pageCount
            if (count <= 0) return emptyList()

            // Za višestranične račune (npr. EPS/telekom) uplatnica i QR su na 1, 2. ili poslednjoj strani.
            val indices = if (count <= 3) {
                (0 until count).toList()
            } else {
                listOf(0, 1, count - 1)
            }

            for (index in indices) {
                renderer.openPage(index).use { page ->
                    val maxDim = max(page.width, page.height).coerceAtLeast(1)
                    val scale = max(2000f / maxDim.toFloat(), 2.0f).coerceAtMost(4.0f)
                    val width = (page.width * scale).roundToInt().coerceAtLeast(1)
                    val height = (page.height * scale).roundToInt().coerceAtLeast(1)

                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    // PDF stranice nemaju podrazumevanu pozadinu — popuni belom bojom radi QR/OCR čitljivosti.
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    bitmap.recycle()
                    outputPages.add(out.toByteArray())
                }
            }
        } catch (_: Exception) {
            // U slučaju neispravnog ili zaključanog PDF-a vraća ono što je do sada uspešno renderovano.
        } finally {
            try {
                renderer?.close()
            } catch (_: Exception) {}
            try {
                pfd?.close()
            } catch (_: Exception) {}
            try {
                tempFile?.delete()
            } catch (_: Exception) {}
        }

        return outputPages
    }

    private fun getAppSignatureSha1(): String? {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                packageInfo.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
            val cert = signatures?.firstOrNull()?.toByteArray() ?: return null
            val md = MessageDigest.getInstance("SHA-1")
            val digest = md.digest(cert)
            digest.joinToString("") { "%02X".format(it) }
        } catch (_: Exception) {
            null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleSendIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val mime = intent.type ?: return

        @Suppress("DEPRECATION")
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

        try {
            when {
                mime.startsWith("image/") && uri != null -> {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val bytes = stream.readBytes()
                        sharedImage = bytes
                        sharedPayload = mapOf("type" to "image", "bytes" to bytes)
                    }
                }
                mime == "application/pdf" && uri != null -> {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val bytes = stream.readBytes()
                        sharedPayload = mapOf("type" to "pdf", "bytes" to bytes)
                    }
                }
                mime.startsWith("text/") -> {
                    val extraText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!extraText.isNullOrBlank()) {
                        sharedPayload = mapOf("type" to "text", "text" to extraText)
                    } else if (uri != null) {
                        contentResolver.openInputStream(uri)?.use { stream ->
                            val text = stream.readBytes().toString(Charsets.UTF_8)
                            if (text.isNotBlank()) {
                                sharedPayload = mapOf("type" to "text", "text" to text)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {
            // Podeljeni sadržaj nije dostupan — ignoriši, aplikacija se normalno otvara.
        }

        // Ukloni EXTRA_STREAM i EXTRA_TEXT da se ne obrade ponovo pri recreate-u.
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
    }
}
