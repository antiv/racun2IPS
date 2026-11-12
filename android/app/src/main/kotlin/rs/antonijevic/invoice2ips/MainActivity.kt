package rs.antonijevic.invoice2ips

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.text.Html
import com.googlecode.tesseract.android.TessBaseAPI
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Prijem slike, PDF dokumenta ili teksta podeljenog iz druge aplikacije (ACTION_SEND),
 * nativno renderovanje PDF stranica u slike pomoću Android PdfRenderer-a,
 * čitanje tekstualnog sloja PDF-a (pdfbox-android) i lokalni ćirilični OCR (Tesseract 4).
 */
class MainActivity : FlutterActivity() {

    companion object {
        private var sharedImage: ByteArray? = null
        private var sharedPayload: Map<String, Any?>? = null
        private val tesseractLock = Any()
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
                "recognizeTextNative" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val ocrResult = recognizeTextWithTesseract(path)
                        runOnUiThread {
                            result.success(ocrResult)
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
     * Kopira ugrađeni srpski ćirilični Tesseract LSTM model (`assets/tessdata/srp.traineddata`)
     * u `filesDir/tessdata/srp.traineddata` pri prvom pozivu.
     */
    private fun ensureTessDataReady(): File? {
        return try {
            val tessDir = File(filesDir, "tessdata")
            if (!tessDir.exists()) {
                tessDir.mkdirs()
            }
            val targetFile = File(tessDir, "srp.traineddata")
            // Zvanični srp.traineddata je ~2.15 MB (2,149,931 bajtova).
            if (!targetFile.exists() || targetFile.length() < 2_000_000L) {
                val assetKey = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/tessdata/srp.traineddata")
                val tmpFile = File(tessDir, "srp.traineddata.tmp")
                assets.open(assetKey).use { input ->
                    tmpFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                if (tmpFile.length() >= 2_000_000L) {
                    if (targetFile.exists()) targetFile.delete()
                    tmpFile.renameTo(targetFile)
                }
            }
            if (targetFile.exists() && targetFile.length() >= 2_000_000L) {
                filesDir
            } else {
                android.util.Log.e("Invoice2IPS", "srp.traineddata nije pronađen ili je neispravne veličine")
                null
            }
        } catch (e: Throwable) {
            android.util.Log.e("Invoice2IPS", "ensureTessDataReady error: $e", e)
            null
        }
    }

    /**
     * Učitava sliku sa diska, primenjuje EXIF orijentaciju i skalira tako da duža
     * strana bude između 2000px i 2400px (optimalno za sitan tekst uplatnice u Tesseract LSTM-u).
     */
    private fun decodeUprightBitmap(filePath: String): Bitmap? {
        return try {
            val boundsOpts = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(filePath, boundsOpts)
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

            var sampleSize = 1
            val rawLongest = max(boundsOpts.outWidth, boundsOpts.outHeight)
            while ((rawLongest / (sampleSize * 2)) >= 2400) {
                sampleSize *= 2
            }

            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            var bmp = BitmapFactory.decodeFile(filePath, opts) ?: return null

            val exif = try {
                ExifInterface(filePath)
            } catch (_: Exception) {
                null
            }
            val rotation = when (exif?.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (rotation != 0f) {
                val matrix = Matrix().apply { postRotate(rotation) }
                val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                if (rotated !== bmp) bmp.recycle()
                bmp = rotated
            }

            val longest = max(bmp.width, bmp.height)
            if (longest in 1..1599) {
                val scale = 2000f / longest.toFloat()
                val scaled = Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * scale).roundToInt().coerceAtLeast(1),
                    (bmp.height * scale).roundToInt().coerceAtLeast(1),
                    true
                )
                if (scaled !== bmp) bmp.recycle()
                bmp = scaled
            } else if (longest > 2600) {
                val scale = 2400f / longest.toFloat()
                val scaled = Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * scale).roundToInt().coerceAtLeast(1),
                    (bmp.height * scale).roundToInt().coerceAtLeast(1),
                    true
                )
                if (scaled !== bmp) bmp.recycle()
                bmp = scaled
            }

            if (bmp.config != Bitmap.Config.ARGB_8888 || !bmp.isMutable) {
                val argb = bmp.copy(Bitmap.Config.ARGB_8888, true)
                bmp.recycle()
                bmp = argb
            }
            removeFormLines(bmp)
            bmp
        } catch (e: Throwable) {
            android.util.Log.e("Invoice2IPS", "decodeUprightBitmap error: $e", e)
            null
        }
    }

    /**
     * Uklanja tanke horizontalne i vertikalne linije okvira (tabelarnih ćelija i boksova
     * uplatnice) kako Tesseract ne bi spojio okvir boksa sa tekstom unutar njega,
     * pri čemu čuva sve piksele slova čak i kada dodiruju liniju okvira.
     */
    private fun removeFormLines(bmp: Bitmap) {
        val w = bmp.width
        val h = bmp.height
        if (w < 100 || h < 100) return

        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)

        val lum = IntArray(w * h)
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            lum[i] = (r * 77 + g * 150 + b * 29) shr 8
        }

        val scale = max(w, h) / 2000f
        val maxThick = (5f * scale).roundToInt().coerceIn(3, 7)
        val minHorizRun = (48f * scale).roundToInt().coerceAtLeast(35)
        val minVertRun = (36f * scale).roundToInt().coerceAtLeast(28)
        val maxGap = (6f * scale).roundToInt().coerceIn(3, 8)
        val contrast = 22

        val rowBg = IntArray(w)
        for (y in maxThick until (h - maxThick)) {
            val rowOffset = y * w
            var runStart = -1
            var runLen = 0
            var gapCount = 0

            for (x in 0 until w) {
                val idx = rowOffset + x
                val l = lum[idx]
                var maxAbove = 0
                var maxBelow = 0
                for (d in 1..maxThick) {
                    val la = lum[(y - d) * w + x]
                    if (la > maxAbove) maxAbove = la
                    val lb = lum[(y + d) * w + x]
                    if (lb > maxBelow) maxBelow = lb
                }
                val isThinDark = (maxAbove - l >= contrast) && (maxBelow - l >= contrast)
                if (isThinDark) {
                    if (runStart < 0) runStart = x
                    runLen++
                    gapCount = 0
                    rowBg[x] = (maxAbove + maxBelow) shr 1
                } else {
                    rowBg[x] = 0
                    if (runStart >= 0 && l < 180 && gapCount < maxGap) {
                        runLen++
                        gapCount++
                    } else {
                        if (runLen >= minHorizRun) {
                            for (kx in runStart until (x - gapCount)) {
                                val bg = rowBg[kx]
                                if (bg > 0) {
                                    val v = bg.coerceIn(225, 255)
                                    pixels[rowOffset + kx] =
                                        (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                                }
                            }
                        }
                        runStart = -1
                        runLen = 0
                        gapCount = 0
                    }
                }
            }
            if (runLen >= minHorizRun && runStart >= 0) {
                for (kx in runStart until (w - gapCount)) {
                    val bg = rowBg[kx]
                    if (bg > 0) {
                        val v = bg.coerceIn(225, 255)
                        pixels[rowOffset + kx] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                    }
                }
            }
        }

        val colBg = IntArray(h)
        for (x in maxThick until (w - maxThick)) {
            var runStart = -1
            var runLen = 0
            var gapCount = 0

            for (y in 0 until h) {
                val rowOff = y * w
                val idx = rowOff + x
                val l = lum[idx]
                var maxLeft = 0
                var maxRight = 0
                for (d in 1..maxThick) {
                    val ll = lum[rowOff + x - d]
                    if (ll > maxLeft) maxLeft = ll
                    val lr = lum[rowOff + x + d]
                    if (lr > maxRight) maxRight = lr
                }
                val isThinDark = (maxLeft - l >= contrast) && (maxRight - l >= contrast)
                if (isThinDark) {
                    if (runStart < 0) runStart = y
                    runLen++
                    gapCount = 0
                    colBg[y] = (maxLeft + maxRight) shr 1
                } else {
                    colBg[y] = 0
                    if (runStart >= 0 && l < 180 && gapCount < maxGap) {
                        runLen++
                        gapCount++
                    } else {
                        if (runLen >= minVertRun) {
                            for (ky in runStart until (y - gapCount)) {
                                val bg = colBg[ky]
                                if (bg > 0) {
                                    val v = bg.coerceIn(225, 255)
                                    pixels[ky * w + x] =
                                        (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                                }
                            }
                        }
                        runStart = -1
                        runLen = 0
                        gapCount = 0
                    }
                }
            }
            if (runLen >= minVertRun && runStart >= 0) {
                for (ky in runStart until (h - gapCount)) {
                    val bg = colBg[ky]
                    if (bg > 0) {
                        val v = bg.coerceIn(225, 255)
                        pixels[ky * w + x] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                    }
                }
            }
        }

        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
    }

    /**
     * Izvršava lokalni ćirilični OCR pomoću Tesseract 4 LSTM modela (`srp.traineddata`)
     * i vraća pun tekst zajedno sa segmentima linija i njihovim koordinatama (`left`, `top`, `right`, `bottom`)
     * iz hOCR izlaza radi geometrijske rekonstrukcije kolona i redova tabele.
     */
    private fun recognizeTextWithTesseract(filePath: String): Map<String, Any>? {
        synchronized(tesseractLock) {
            val dataParent = ensureTessDataReady() ?: return null
            val bitmap = decodeUprightBitmap(filePath) ?: return null
            val tess = TessBaseAPI()
            try {
                val initialized = tess.init(
                    dataParent.absolutePath,
                    "srp",
                    TessBaseAPI.OEM_LSTM_ONLY
                )
                if (!initialized) {
                    return null
                }
                tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT
                tess.setImage(bitmap)

                val fullText = tess.utF8Text ?: ""
                val hocr = tess.getHOCRText(0) ?: ""

                val lineHeaderRegex = Regex(
                    """<span\s+class=['"](?:ocr_line|ocr_header|ocr_caption|ocr_textfloat)['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+);[^'"]*['"][^>]*>""",
                    RegexOption.IGNORE_CASE
                )
                val wordRegex = Regex(
                    """<span\s+class=['"]ocrx_word['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+);[^'"]*['"][^>]*>(.*?)</span>""",
                    setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE)
                )
                val tagStripRegex = Regex("""<[^>]+>""")
                val lines = mutableListOf<Map<String, Any>>()

                fun decodeHtmlText(raw: String): String {
                    val stripped = raw.replace(tagStripRegex, " ")
                    val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        Html.fromHtml(stripped, Html.FROM_HTML_MODE_LEGACY).toString()
                    } else {
                        @Suppress("DEPRECATION")
                        Html.fromHtml(stripped).toString()
                    }
                    return decoded.replace(Regex("""\s+"""), " ").trim()
                }

                val lineHeaders = lineHeaderRegex.findAll(hocr).toList()
                for (idx in lineHeaders.indices) {
                    val match = lineHeaders[idx]
                    val lineLeft = match.groupValues[1].toDoubleOrNull() ?: continue
                    val lineTop = match.groupValues[2].toDoubleOrNull() ?: continue
                    val lineRight = match.groupValues[3].toDoubleOrNull() ?: continue
                    val lineBottom = match.groupValues[4].toDoubleOrNull() ?: continue
                    val chunkStart = match.range.last + 1
                    val chunkEnd = if (idx + 1 < lineHeaders.size) {
                        lineHeaders[idx + 1].range.first
                    } else {
                        hocr.length
                    }
                    val innerHtml = hocr.substring(chunkStart, chunkEnd)

                    // Razdvoji reči u istoj liniji kada postoji horizontalni razmak između
                    // susednih kolona uplatnice ili tabele, tako da svaka ćelija zadrži sopstveni bbox.
                    val wordMatches = wordRegex.findAll(innerHtml).toList()
                    if (wordMatches.isNotEmpty()) {
                        var segWords = mutableListOf<String>()
                        var segLeft = 0.0
                        var segTop = 0.0
                        var segRight = 0.0
                        var segBottom = 0.0

                        fun flushSegment() {
                            val text = segWords.joinToString(" ").trim()
                            if (text.isNotEmpty()) {
                                lines.add(
                                    mapOf(
                                        "text" to text,
                                        "left" to segLeft,
                                        "top" to segTop,
                                        "right" to segRight,
                                        "bottom" to segBottom
                                    )
                                )
                            }
                            segWords = mutableListOf()
                        }

                        for (wm in wordMatches) {
                            val wLeft = wm.groupValues[1].toDoubleOrNull() ?: continue
                            val wTop = wm.groupValues[2].toDoubleOrNull() ?: continue
                            val wRight = wm.groupValues[3].toDoubleOrNull() ?: continue
                            val wBottom = wm.groupValues[4].toDoubleOrNull() ?: continue
                            val wText = decodeHtmlText(wm.groupValues[5])
                            if (wText.isEmpty()) continue

                            if (segWords.isEmpty()) {
                                segWords.add(wText)
                                segLeft = wLeft
                                segTop = wTop
                                segRight = wRight
                                segBottom = wBottom
                            } else {
                                val segHeight = max(1.0, segBottom - segTop)
                                val gap = wLeft - segRight
                                if (gap > max(segHeight * 2.2, 45.0)) {
                                    flushSegment()
                                    segWords.add(wText)
                                    segLeft = wLeft
                                    segTop = wTop
                                    segRight = wRight
                                    segBottom = wBottom
                                } else {
                                    segWords.add(wText)
                                    segTop = min(segTop, wTop)
                                    segRight = max(segRight, wRight)
                                    segBottom = max(segBottom, wBottom)
                                }
                            }
                        }
                        flushSegment()
                    } else {
                        val cleanLine = decodeHtmlText(innerHtml)
                        if (cleanLine.isNotEmpty()) {
                            lines.add(
                                mapOf(
                                    "text" to cleanLine,
                                    "left" to lineLeft,
                                    "top" to lineTop,
                                    "right" to lineRight,
                                    "bottom" to lineBottom
                                )
                            )
                        }
                    }
                }

                val segmentedText = if (lines.isNotEmpty()) {
                    lines.joinToString("\n") { it["text"] as String }
                } else {
                    fullText
                }

                return mapOf(
                    "text" to segmentedText,
                    "lines" to lines
                )
            } catch (e: Throwable) {
                android.util.Log.e("Invoice2IPS", "recognizeTextWithTesseract error: $e", e)
                return null
            } finally {
                try {
                    tess.recycle()
                } catch (_: Throwable) {}
                try {
                    bitmap.recycle()
                } catch (_: Throwable) {}
            }
        }
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
