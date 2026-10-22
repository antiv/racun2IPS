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
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Prijem slike, PDF dokumenta ili teksta podeljenog iz druge aplikacije (ACTION_SEND),
 * nativno renderovanje PDF stranica u slike pomoću Android PdfRenderer-a i
 * čitanje tekstualnog sloja PDF-a (pdfbox-android).
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
                    val pdfBytes = pdfBytesArgument(call.argument<Any>("bytes"))
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
                "extractPdfText" -> {
                    val pdfBytes = pdfBytesArgument(call.argument<Any>("bytes"))
                    if (pdfBytes == null || pdfBytes.isEmpty()) {
                        result.success(emptyList<String>())
                        return@setMethodCallHandler
                    }
                    Thread {
                        val texts = extractPdfTextPages(pdfBytes)
                        runOnUiThread {
                            result.success(texts)
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

    private fun pdfBytesArgument(raw: Any?): ByteArray? = when (raw) {
        is ByteArray -> raw
        is List<*> -> ByteArray(raw.size) { (raw[it] as Number).toByte() }
        else -> null
    }

    /**
     * Čita tekstualni sloj PDF-a za iste stranice koje se renderuju (sve do 3,
     * inače 1, 2. i poslednju). PDF računi (npr. EPS) obično imaju tačan tekst
     * na ćirilici, koji lokalni OCR (samo latinica) ne može da pročita sa slike.
     * Skenirani PDF bez tekstualnog sloja vraća prazne stringove.
     */
    private fun extractPdfTextPages(pdfBytes: ByteArray): List<String> {
        return try {
            PDFBoxResourceLoader.init(applicationContext)
            PDDocument.load(pdfBytes).use { document ->
                val count = document.numberOfPages
                val indices = if (count <= 3) (0 until count).toList() else listOf(0, 1, count - 1)
                val stripper = PDFTextStripper()
                indices.map { index ->
                    stripper.startPage = index + 1
                    stripper.endPage = index + 1
                    stripper.getText(document)
                }
            }
        } catch (_: Throwable) {
            // Zaključan ili neispravan PDF — Dart strana nastavlja sa QR/OCR/AI tokom.
            emptyList()
        }
    }

    /**
     * Renderuje stranice PDF dokumenta u PNG slike visoke rezolucije (~3000px po dužoj strani,
     * da i sitan IPS QR kod na strani ima dovoljno piksela po modulu za ML Kit)
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
                    val scale = max(3000f / maxDim.toFloat(), 2.0f).coerceAtMost(4.0f)
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
        setIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE && action != Intent.ACTION_VIEW) return

        @Suppress("DEPRECATION")
        val streamUri: Uri? = (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }) ?: runCatching {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.firstOrNull()
        }.getOrNull() ?: intent.getStringExtra(Intent.EXTRA_STREAM)?.let {
            runCatching { Uri.parse(it) }.getOrNull()
        }

        val clipUri: Uri? = if (intent.clipData != null && intent.clipData!!.itemCount > 0) {
            intent.clipData!!.getItemAt(0).uri
        } else {
            null
        }
        val dataUri: Uri? = intent.data
        // Prioritet: clipUri (gde sistem obično delegira URI permission) -> streamUri -> dataUri
        val uri: Uri? = clipUri ?: streamUri ?: dataUri

        val rawMime = intent.type ?: uri?.let {
            try {
                contentResolver.getType(it)
            } catch (_: Exception) {
                null
            }
        } ?: ""

        val uriString = uri?.toString()?.lowercase() ?: ""
        var isPdf = rawMime.contains("pdf", ignoreCase = true) || uriString.contains(".pdf")
        var isImage = rawMime.startsWith("image/") ||
                listOf(".png", ".jpg", ".jpeg", ".webp").any { uriString.contains(it) }

        android.util.Log.i(
            "Invoice2IPS",
            "handleSendIntent: action=$action, rawMime=$rawMime, uri=$uri, isPdf=$isPdf, isImage=$isImage"
        )

        try {
            val bytes = if (uri != null) {
                try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (e: Exception) {
                    android.util.Log.w("Invoice2IPS", "openInputStream nije uspeo ($e), probam openFileDescriptor...")
                    try {
                        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                            FileInputStream(pfd.fileDescriptor).use { it.readBytes() }
                        }
                    } catch (e2: Exception) {
                        android.util.Log.w("Invoice2IPS", "openFileDescriptor nije uspeo: $e2")
                        if (uri.scheme == "file") {
                            val file = File(uri.path ?: "")
                            if (file.exists() && file.canRead()) file.readBytes() else null
                        } else {
                            null
                        }
                    }
                }
            } else {
                null
            }

            if (bytes != null && bytes.isNotEmpty()) {
                // Magic byte provera za 100% tačnu detekciju formata
                val isPdfMagic = bytes.size >= 4 &&
                        bytes[0] == 0x25.toByte() && // %
                        bytes[1] == 0x50.toByte() && // P
                        bytes[2] == 0x44.toByte() && // D
                        bytes[3] == 0x46.toByte()    // F
                val isPngMagic = bytes.size >= 8 &&
                        bytes[0] == 0x89.toByte() &&
                        bytes[1] == 0x50.toByte() &&
                        bytes[2] == 0x4E.toByte() &&
                        bytes[3] == 0x47.toByte()
                val isJpgMagic = bytes.size >= 3 &&
                        bytes[0] == 0xFF.toByte() &&
                        bytes[1] == 0xD8.toByte() &&
                        bytes[2] == 0xFF.toByte()

                if (isPdfMagic) {
                    isPdf = true
                    isImage = false
                } else if (isPngMagic || isJpgMagic) {
                    isImage = true
                    isPdf = false
                }

                if (isPdf) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni PDF: ${bytes.size} bajtova")
                    sharedPayload = mapOf("type" to "pdf", "bytes" to bytes)
                } else if (isImage) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitana deljena slika: ${bytes.size} bajtova")
                    sharedImage = bytes
                    sharedPayload = mapOf("type" to "image", "bytes" to bytes)
                } else {
                    android.util.Log.w("Invoice2IPS", "Nepoznat binarni format fajla (${bytes.size} bajtova)")
                }
            } else {
                val extraText = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!extraText.isNullOrBlank()) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni tekst iz EXTRA_TEXT")
                    sharedPayload = mapOf("type" to "text", "text" to extraText)
                } else if (rawMime.startsWith("text/") && uri != null) {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val text = stream.readBytes().toString(Charsets.UTF_8)
                        if (text.isNotBlank()) {
                            android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni tekst iz URI-ja")
                            sharedPayload = mapOf("type" to "text", "text" to text)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("Invoice2IPS", "Greska pri ucitavanju deljenog sadrzaja: $e", e)
        }

        // Ukloni extras i data da se ne obrade ponovo pri recreate-u
        intent.data = null
        intent.clipData = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
    }
}
